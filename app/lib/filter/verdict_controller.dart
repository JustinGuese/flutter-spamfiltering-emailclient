import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:df_funnel/df_funnel.dart';
import 'package:df_firebase_auth/df_firebase_auth.dart';
import 'package:spam_core/spam_core.dart';
import 'package:sqlite3/sqlite3.dart' show Row;
import '../community/matcher.dart';
import '../community/report_client.dart';
import '../db/database.dart';
import '../mail/account_repository.dart';
import '../mail/imap_service.dart';
import '../mail/sync_engine.dart';
import '../mail/unsubscribe_service.dart';
import '../premium/crdt_counters.dart';
import '../premium/filter_sync.dart';
import 'imap_flags.dart';
import 'token_store_drift.dart';
import '../app/log.dart';

class UndoRecord {
  final String messageId;
  final Label previousLabel;
  final Label newLabel;
  final String previousFolderId;
  final Timer timer;

  /// Duplicates that were marked together with [messageId]; undo restores them too.
  final List<({String messageId, Label previousLabel})> duplicates;

  UndoRecord({
    required this.messageId,
    required this.previousLabel,
    required this.newLabel,
    required this.previousFolderId,
    required this.timer,
    this.duplicates = const [],
  });
}

/// What [VerdictController._applyOne] changed, so the caller can cascade and undo.
class _Applied {
  final Label prevLabel;
  final String prevFolderId;
  final Normalized normalized;
  final int similarCount;
  const _Applied(this.prevLabel, this.prevFolderId, this.normalized, this.similarCount);
}

class VerdictController {
  final AppDatabase db;
  final TokenStoreDrift tokenStore;
  final AccountRepository? accountRepo;
  final CommunityReportClient? reportClient;
  final FilterSyncService? filterSyncService;
  final UnsubscribeService? unsubscribeService;
  final bool isPro;
  final bool isSignedIn;
  final void Function()? onFirstSpamNotice;

  /// Called after the local database changed, so lists and the reader rebuild.
  final void Function()? onChanged;

  UndoRecord? _activeUndo;
  DateTime? _lastUploadTime;
  Timer? _debounceTimer;
  /// One pending auto-unsubscribe per message, so spam-clicking several
  /// messages in a row does not drop all but the last.
  final Map<String, Timer> _pendingUnsubscribes = {};
  bool _isExecutingUndo = false;
  Future<void> _imapQueue = Future.value();

  VerdictController({
    required this.db,
    required this.tokenStore,
    this.accountRepo,
    this.reportClient,
    this.filterSyncService,
    this.unsubscribeService,
    this.isPro = false,
    this.isSignedIn = false,
    this.onFirstSpamNotice,
    this.onChanged,
  });

  UndoRecord? get activeUndo => _activeUndo;
  Timer? get pendingUnsubscribeTimer => _pendingUnsubscribes.values.lastOrNull;
  String? get pendingUnsubscribeMessageId => _pendingUnsubscribes.keys.lastOrNull;
  bool hasPendingUnsubscribe(String messageId) => _pendingUnsubscribes.containsKey(messageId);

  Future<int> applyVerdict({
    required String messageId,
    required Label newLabel,
    void Function(String messageId, Label label, int similarCount)? onStamp,
  }) async {
    final applied = _applyOne(messageId, newLabel, onStamp: onStamp);
    if (applied == null) return 0;

    // Marking one copy of a mail as spam also filters its identical copies in the
    // inbox (the same mail is often delivered several times). Never on undo, which
    // restores the copies from the undo record instead.
    final duplicates = <({String messageId, Label previousLabel})>[];
    if (newLabel == Label.spam && !_isExecutingUndo) {
      for (final id in _findDuplicates(messageId, applied.normalized)) {
        final dup = _applyOne(id, Label.spam);
        if (dup != null) duplicates.add((messageId: id, previousLabel: dup.prevLabel));
      }
    }

    _handleCommunityReporting(applied.normalized, applied.prevLabel, newLabel);
    _triggerPremiumSyncDebounced();
    _handleUnsubscribeScheduling(messageId, newLabel, isUndo: _isExecutingUndo);

    _activeUndo?.timer.cancel();
    _activeUndo = UndoRecord(
      messageId: messageId,
      previousLabel: applied.prevLabel,
      newLabel: newLabel,
      previousFolderId: applied.prevFolderId,
      timer: Timer(const Duration(seconds: 8), () => _activeUndo = null),
      duplicates: duplicates,
    );
    return applied.similarCount;
  }

  /// Writes one message's verdict (labels, token training, IMAP move). Returns null
  /// when the message is gone or already has [newLabel].
  _Applied? _applyOne(
    String messageId,
    Label newLabel, {
    void Function(String messageId, Label label, int similarCount)? onStamp,
  }) {
    final row = db.db.select('''
      SELECT m.id, m.account_id, m.uid, m.folder_id, m.subject, m.sender, m.sender_domain,
             m.recipient_addrs, m.classification_label, b.text_body, b.html_body
      FROM messages m LEFT JOIN bodies b ON m.id = b.message_id WHERE m.id = ?
    ''', [messageId]).firstOrNull;
    if (row == null) return null;

    final prevLabel = Label.values.byName((row['classification_label'] as String?) ?? 'inbox');
    final prevFolderId = row['folder_id'] as String;
    final accountId = row['account_id'] as String;
    final uid = row['uid'] as int;
    if (prevLabel == newLabel) return null;

    final normalized = Normalizer.normalize(_toMessage(row));
    final score = newLabel == Label.spam ? 0.95 : 0.05;

    // One transaction for the whole verdict. A message has hundreds of tokens and
    // each count update is a write; as separate autocommits every one waits for the
    // disk, which froze the UI for ten seconds or more.
    db.db.execute('BEGIN');
    try {
      for (final t in Tokenizer.tokens(normalized)) {
        final h = Tokenizer.hashToken(t);
        tokenStore.apply(h, prevLabel, -1);
        tokenStore.apply(h, newLabel, 1);
      }
      db.db.execute('UPDATE messages SET classification_label = ?, spam_score = ? WHERE id = ?',
          [newLabel.name, score, messageId]);
      db.db.execute('''
        INSERT OR REPLACE INTO classifications
        (message_id, label, spam_score, evidence_json, classified_at, user_overridden)
        VALUES (?, ?, ?, ?, ?, 1)
      ''', [messageId, newLabel.name, score, '[]', DateTime.now().toIso8601String()]);
      db.db.execute('COMMIT');
    } catch (_) {
      db.db.execute('ROLLBACK');
      rethrow;
    }
    onChanged?.call();

    // Other messages from the same sender domain: what this verdict will also help
    // the filter recognise. Real count from the stored domain column.
    final domain = row['sender_domain'] as String?;
    final similarCount = domain == null || domain.isEmpty
        ? 0
        : (db.db.select('SELECT COUNT(*) AS cnt FROM messages WHERE sender_domain = ? AND id != ?',
                    [domain, messageId]).firstOrNull?['cnt'] as int?) ??
            0;
    onStamp?.call(messageId, newLabel, similarCount);

    // Serialised: duplicates must not open parallel IMAP connections.
    _imapQueue = _imapQueue.then((_) => _applyImapEffect(messageId, accountId, uid, prevFolderId, newLabel));
    return _Applied(prevLabel, prevFolderId, normalized, similarCount);
  }

  Message _toMessage(Row row) => Message(
        headers: {'From': [row['sender'] as String], 'Subject': [row['subject'] as String]},
        textBody: (row['text_body'] as String?) ?? '',
        htmlBody: row['html_body'] as String?,
        recipientAddrs: ((row['recipient_addrs'] as String?) ?? '').split(',').map((s) => s.trim()).toList(),
      );

  /// Ids of other copies of [normalized]'s mail that should follow it into Junk: same
  /// account, same sender address, same subject and the same body (identical cleaned
  /// text, or at least 6 of 8 MinHash bands). Skips mail already in Junk/Trash/Sent,
  /// mail already spam, and anything the user judged by hand (`user_overridden`).
  List<String> _findDuplicates(String messageId, Normalized normalized) {
    final origin = db.db.select(
        'SELECT account_id, sender, subject FROM messages WHERE id = ?', [messageId]).firstOrNull;
    if (origin == null) return const [];
    final candidates = db.db.select('''
      SELECT m.id, m.sender, m.subject, m.recipient_addrs, b.text_body, b.html_body
      FROM messages m
      LEFT JOIN bodies b ON m.id = b.message_id
      LEFT JOIN folders f ON f.id = m.folder_id
      LEFT JOIN classifications c ON c.message_id = m.id
      WHERE m.account_id = ? AND m.id != ?
        AND LOWER(TRIM(m.sender)) = LOWER(TRIM(?)) AND LOWER(TRIM(m.subject)) = LOWER(TRIM(?))
        AND m.classification_label != 'spam'
        AND COALESCE(c.user_overridden, 0) = 0
        AND COALESCE(f.special_use, '') NOT IN ('junk', 'trash', 'sent', 'drafts')
      LIMIT 50
    ''', [origin['account_id'], messageId, origin['sender'], origin['subject']]);
    if (candidates.isEmpty) return const [];

    final bands = Fingerprinter.fingerprints(normalized).bodyBands.toSet();
    final ids = <String>[];
    for (final row in candidates) {
      final other = Normalizer.normalize(_toMessage(row));
      if (other.cleanedText == normalized.cleanedText) {
        ids.add(row['id'] as String);
        continue;
      }
      final otherBands = Fingerprinter.fingerprints(other).bodyBands;
      if (bands.isNotEmpty && otherBands.isNotEmpty && otherBands.where(bands.contains).length >= 6) {
        ids.add(row['id'] as String);
      }
    }
    return ids;
  }

  void _handleUnsubscribeScheduling(String messageId, Label newLabel, {required bool isUndo}) {
    // Any non-spam verdict, and spam applied as the undo of a ham verdict,
    // cancels this message's pending unsubscribe and never schedules one.
    _cancelPendingUnsubscribe(messageId);
    if (newLabel != Label.spam || isUndo) return;

    // Spam click schedules unsubscribe after 10 seconds (past the 8 s undo window).
    final service = unsubscribeService;
    if (service == null) return;
    _pendingUnsubscribes[messageId] = Timer(const Duration(seconds: 10), () {
      _pendingUnsubscribes.remove(messageId);
      service.unsubscribeForMessage(messageId, trigger: UnsubscribeTrigger.verdict).catchError((Object e, StackTrace st) {
        logError('auto unsubscribe $messageId', e, st);
        return const UnsubscribeOutcome(UnsubscribeStatus.failed);
      });
    });
  }

  void _cancelPendingUnsubscribe(String messageId) {
    _pendingUnsubscribes.remove(messageId)?.cancel();
  }

  void _handleCommunityReporting(Normalized normalized, Label prev, Label next) {
    if (next == Label.spam) {
      final seen = db.db.select("SELECT value FROM settings WHERE key = 'sharing_notice_seen'").firstOrNull;
      if (seen == null || seen['value'] != 'true') onFirstSpamNotice?.call();
      final share = db.db.select("SELECT value FROM settings WHERE key = 'share_spam_fingerprints'").firstOrNull;
      if (share == null || share['value'] == 'true') {
        final fp = Fingerprinter.fingerprints(normalized);
        (reportClient ?? CommunityReportClient()).reportSpam(fp).then((ok) {
          if (ok) {
            db.db.execute("INSERT OR REPLACE INTO settings (key, value) VALUES ('last_report_at', ?)",
                [DateTime.now().toIso8601String()]);
          }
        });
      }
    } else if (prev == Label.spam && (next == Label.ham || next == Label.inbox)) {
      final fp = Fingerprinter.fingerprints(normalized);
      final matcher = CommunityMatcher(db);
      if (matcher.matches(fp)) {
        final hashes = matcher.matchingHashes(fp);
        if (hashes.isNotEmpty) (reportClient ?? CommunityReportClient()).voteHam(hashes);
      }
    }
  }

  Future<void> _applyImapEffect(String msgId, String accId, int uid, String prevFolderId, Label label) async {
    try {
      final account = accountRepo?.listAccounts().where((a) => a.id == accId).firstOrNull;
      final auth = await accountRepo?.getAuthForAccount(accId);
      if (account == null || auth == null) return;

      final imap = ImapService();
      await imap.connectAndAuthenticate(account, auth);
      final folderRow = db.db.select('SELECT server_path FROM folders WHERE id = ?', [prevFolderId]).firstOrNull;
      final curPath = (folderRow?['server_path'] as String?) ?? 'INBOX';
      final mailbox = await imap.selectMailbox(curPath);

      if (label == Label.spam) {
        final junk = db.db.select(
          "SELECT server_path, id FROM folders WHERE account_id = ? AND (special_use = 'junk' OR LOWER(name) LIKE '%junk%' OR LOWER(name) LIKE '%spam%') LIMIT 1",
          [accId],
        ).firstOrNull;
        await ImapFlagsManager.markSpam(imap, uid);
        if (junk != null) {
          await imap.moveMessage(uid, junk['server_path'] as String);
          db.db.execute('UPDATE messages SET folder_id = ? WHERE id = ?', [junk['id'], msgId]);
          onChanged?.call();
        }
      } else if (label == Label.inbox || label == Label.ham) {
        final inbox = db.db.select(
          "SELECT server_path, id FROM folders WHERE account_id = ? AND (special_use = 'inbox' OR LOWER(name) = 'inbox') LIMIT 1",
          [accId],
        ).firstOrNull;
        await ImapFlagsManager.markHam(imap, uid);
        if (inbox != null && curPath != inbox['server_path']) {
          await imap.moveMessage(uid, inbox['server_path'] as String);
          db.db.execute('UPDATE messages SET folder_id = ? WHERE id = ?', [inbox['id'], msgId]);
          onChanged?.call();
        }
      } else if (label == Label.newsletter && mailbox.permanentMessageFlags.contains(r'\*')) {
        await ImapFlagsManager.markNewsletter(imap, uid, serverSupportsPermanentFlags: true);
      }
      await imap.disconnect();
    } catch (e, st) {
      logError('verdict imap effect', e, st);
      final target = label == Label.spam ? 'junk' : (label == Label.inbox ? 'inbox' : null);
      final act = label == Label.spam ? 'mark_spam' : (label == Label.newsletter ? 'mark_newsletter' : 'mark_ham');
      db.db.execute('INSERT INTO pending_imap_actions (account_id, message_id, uid, folder_id, action, target_folder) VALUES (?, ?, ?, ?, ?, ?)',
          [accId, msgId, uid, prevFolderId, act, target]);
    }
  }

  void _triggerPremiumSyncDebounced() {
    if (!isPro || !isSignedIn || filterSyncService == null) return;
    final row = db.db.select("SELECT value FROM settings WHERE key = 'filter_sync_enabled'").firstOrNull;
    if (row != null && row['value'] == 'false') return;

    final now = DateTime.now();
    if (_lastUploadTime == null || now.difference(_lastUploadTime!) >= const Duration(minutes: 1)) {
      _lastUploadTime = now;
      _uploadCrdtState();
    } else {
      _debounceTimer?.cancel();
      final wait = const Duration(minutes: 1) - now.difference(_lastUploadTime!);
      _debounceTimer = Timer(wait, () {
        _lastUploadTime = DateTime.now();
        _uploadCrdtState();
      });
    }
  }

  void _uploadCrdtState() {
    final rows = db.db.select('SELECT hash, spam, ham FROM tokens');
    final spamMap = <int, PNCounter>{};
    final hamMap = <int, PNCounter>{};
    for (final r in rows) {
      final h = (r['hash'] as num).toInt();
      final s = (r['spam'] as int?) ?? 0;
      final hm = (r['ham'] as int?) ?? 0;
      if (s != 0) spamMap[h] = PNCounter(positive: s > 0 ? s : 0, negative: s < 0 ? -s : 0);
      if (hm != 0) hamMap[h] = PNCounter(positive: hm > 0 ? hm : 0, negative: hm < 0 ? -hm : 0);
    }
    filterSyncService!.uploadDeviceState(
      CrdtTokenState(deviceId: filterSyncService!.deviceSlot, spamTokens: spamMap, hamTokens: hamMap),
    );
  }

  void undo() {
    final record = _activeUndo;
    if (record == null) return;
    _cancelPendingUnsubscribe(record.messageId);
    record.timer.cancel();
    _activeUndo = null;
    _isExecutingUndo = true;
    try {
      applyVerdict(messageId: record.messageId, newLabel: record.previousLabel);
      for (final dup in record.duplicates) {
        _applyOne(dup.messageId, dup.previousLabel);
      }
    } finally {
      _isExecutingUndo = false;
    }
  }
}

class SharingNoticeVisibleNotifier extends Notifier<bool> {
  @override
  bool build() => false;
  void show() => state = true;
  void hide() => state = false;
}

final sharingNoticeVisibleProvider =
    NotifierProvider<SharingNoticeVisibleNotifier, bool>(SharingNoticeVisibleNotifier.new);

final verdictControllerProvider = Provider<VerdictController>((ref) => VerdictController(
  db: ref.watch(databaseProvider),
  tokenStore: ref.watch(tokenStoreProvider),
  accountRepo: ref.watch(accountRepositoryProvider),
  reportClient: CommunityReportClient(),
  filterSyncService: ref.watch(filterSyncServiceProvider),
  unsubscribeService: ref.watch(unsubscribeServiceProvider),
  isPro: ref.watch(dfEffectivePremiumProvider),
  isSignedIn: ref.watch(currentUserProvider) != null,
  onFirstSpamNotice: () => ref.read(sharingNoticeVisibleProvider.notifier).show(),
  onChanged: () => ref.read(mailRevisionProvider.notifier).bump(),
));
