import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:df_funnel/df_funnel.dart';
import 'package:df_firebase_auth/df_firebase_auth.dart';
import 'package:spam_core/spam_core.dart';
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

  UndoRecord({
    required this.messageId,
    required this.previousLabel,
    required this.newLabel,
    required this.previousFolderId,
    required this.timer,
  });
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
  Timer? _pendingUnsubscribeTimer;
  String? _pendingUnsubscribeMessageId;
  bool _isExecutingUndo = false;

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
  Timer? get pendingUnsubscribeTimer => _pendingUnsubscribeTimer;
  String? get pendingUnsubscribeMessageId => _pendingUnsubscribeMessageId;

  Future<int> applyVerdict({
    required String messageId,
    required Label newLabel,
    void Function(String messageId, Label label, int similarCount)? onStamp,
  }) async {
    final row = db.db.select('''
      SELECT m.id, m.account_id, m.uid, m.folder_id, m.subject, m.sender, m.sender_domain,
             m.recipient_addrs, m.classification_label, b.text_body, b.html_body
      FROM messages m LEFT JOIN bodies b ON m.id = b.message_id WHERE m.id = ?
    ''', [messageId]).firstOrNull;
    if (row == null) return 0;

    final prevLabel = Label.values.byName((row['classification_label'] as String?) ?? 'inbox');
    final prevFolderId = row['folder_id'] as String;
    final accountId = row['account_id'] as String;
    final uid = row['uid'] as int;
    if (prevLabel == newLabel) return 0;

    final msg = Message(
      headers: {'From': [row['sender'] as String], 'Subject': [row['subject'] as String]},
      textBody: (row['text_body'] as String?) ?? '',
      htmlBody: row['html_body'] as String?,
      recipientAddrs: ((row['recipient_addrs'] as String?) ?? '').split(',').map((s) => s.trim()).toList(),
    );
    final normalized = Normalizer.normalize(msg);
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

    _applyImapEffect(messageId, accountId, uid, prevFolderId, newLabel);
    _handleCommunityReporting(normalized, prevLabel, newLabel);
    _triggerPremiumSyncDebounced();

    _handleUnsubscribeScheduling(messageId, newLabel, isUndo: _isExecutingUndo);

    _activeUndo?.timer.cancel();
    _activeUndo = UndoRecord(
      messageId: messageId,
      previousLabel: prevLabel,
      newLabel: newLabel,
      previousFolderId: prevFolderId,
      timer: Timer(const Duration(seconds: 8), () => _activeUndo = null),
    );
    return similarCount;
  }

  void _handleUnsubscribeScheduling(String messageId, Label newLabel, {required bool isUndo}) {
    // Any non-spam verdict cancels pending unsubscribe
    if (newLabel != Label.spam) {
      _cancelPendingUnsubscribe();
      return;
    }

    // Applying spam as the undo of a ham verdict does NOT schedule auto-unsubscribe.
    if (isUndo) {
      _cancelPendingUnsubscribe();
      return;
    }

    // Spam click schedules unsubscribe after 10 seconds.
    _cancelPendingUnsubscribe();
    if (unsubscribeService != null) {
      _pendingUnsubscribeMessageId = messageId;
      _pendingUnsubscribeTimer = Timer(const Duration(seconds: 10), () {
        unsubscribeService?.unsubscribeForMessage(
          messageId,
          trigger: UnsubscribeTrigger.verdict,
        );
        _pendingUnsubscribeTimer = null;
        _pendingUnsubscribeMessageId = null;
      });
    }
  }

  void _cancelPendingUnsubscribe() {
    _pendingUnsubscribeTimer?.cancel();
    _pendingUnsubscribeTimer = null;
    _pendingUnsubscribeMessageId = null;
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
    _cancelPendingUnsubscribe();
    final record = _activeUndo;
    if (record == null) return;
    record.timer.cancel();
    _activeUndo = null;
    _isExecutingUndo = true;
    try {
      applyVerdict(messageId: record.messageId, newLabel: record.previousLabel);
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
