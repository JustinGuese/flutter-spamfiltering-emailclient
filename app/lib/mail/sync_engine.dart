import 'package:enough_mail/enough_mail.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spam_core/spam_core.dart' as sc;
import '../db/database.dart';
import '../filter/filter_service.dart';
import '../filter/imap_flags.dart';
import 'account_repository.dart';
import '../app/log.dart';
import 'imap_service.dart';
import 'html_sanitizer.dart';
import 'html_to_text.dart';

/// Bumped whenever sync writes mail, so lists reading the local database
/// rebuild. (The UI reads SQLite directly and has no change stream of its own.)
class MailRevisionNotifier extends Notifier<int> {
  @override
  int build() => 0;
  void bump() => state++;
}

final mailRevisionProvider =
    NotifierProvider<MailRevisionNotifier, int>(MailRevisionNotifier.new);

class SyncEngine {
  /// How many of the newest messages a first sync of a folder pulls.
  static const initialFetchCount = 100;

  final AppDatabase db;
  final AccountRepository accountRepo;
  final ImapService imap;
  final FilterService? filterService;
  final void Function()? onChanged;

  SyncEngine({
    required this.db,
    required this.accountRepo,
    ImapService? imap,
    this.filterService,
    this.onChanged,
  }) : imap = imap ?? ImapService();

  // All syncs share one IMAP connection, so they run strictly one at a time,
  // and a second request for an account already syncing joins the first.
  Future<void> _queue = Future.value();
  final _inFlight = <String, Future<void>>{};

  Future<void> syncAccount(String accountId) {
    final running = _inFlight[accountId];
    if (running != null) return running;
    final run = _queue.catchError((Object _) {}).then((_) => _syncAccount(accountId));
    _queue = run.catchError((Object _) {});
    // Block body on purpose: an arrow would return the removed future itself,
    // and whenComplete would then wait on the very future it is completing.
    return _inFlight[accountId] = run.whenComplete(() {
      _inFlight.remove(accountId);
    });
  }

  Future<void> _syncAccount(String accountId) async {
    final accounts = accountRepo.listAccounts();
    final account = accounts.where((a) => a.id == accountId).firstOrNull;
    if (account == null) return;

    final auth = await accountRepo.getAuthForAccount(accountId);
    if (auth == null) {
      // Never skip silently: an account without credentials looks "connected"
      // but stays empty forever.
      throw StateError('No saved password for ${account.email}. Remove the account and add it again.');
    }

    _purgeLegacyUidRows(account.id);
    _backfillHtmlOnlyText(account.id);

    logInfo('sync', 'connecting ${account.email} to ${account.imapHost}:${account.imapPort}');
    await imap.connectAndAuthenticate(account, auth);
    logInfo('sync', 'logged in');
    try {
      final folders = await imap.listSpecialUseFolders();
      logInfo('sync', '${folders.length} folders: ${folders.map((f) => f.serverPath).join(', ')}');
      final junkFolder = folders.where((f) => f.specialUse == 'junk').firstOrNull;

      // Inbox first, so mail shows up before slower folders are even listed.
      final selectable = folders.where((f) => f.selectable).toList()
        ..sort((a, b) => (b.specialUse == 'inbox' ? 1 : 0) - (a.specialUse == 'inbox' ? 1 : 0));

      for (final folder in selectable) {
        final folderId = '${account.id}_${folder.serverPath}';
        db.db.execute('''
          INSERT OR REPLACE INTO folders (id, account_id, name, server_path, special_use, unread_count)
          VALUES (?, ?, ?, ?, ?, ?)
        ''', [
          folderId,
          account.id,
          folder.name,
          folder.serverPath,
          folder.specialUse,
          folder.messagesCount,
        ]);
        onChanged?.call();

        if (folder.specialUse == 'inbox' || folder.specialUse == null) {
          try {
            await _syncFolderMessages(account.id, folderId, folder.serverPath, junkFolder);
          } catch (e, st) {
            // One unreadable folder must not abort the inbox or the rest.
            logError('sync folder ${folder.serverPath}', e, st);
            if (folder.specialUse == 'inbox') rethrow;
          }
        }
      }

      await _processPendingImapActions(account);
    } finally {
      try {
        await imap.disconnect();
      } catch (e) {
        logError('imap disconnect', e);
      }
    }
  }

  /// Earlier builds keyed rows by IMAP *sequence number* (and fetched the
  /// oldest 30 messages). Those rows have wrong uids and would stop the new
  /// UID-based sync from ever fetching the real mail, so they are dropped once;
  /// the cache is rebuilt from the server.
  /// Mail with only an HTML part was stored with an empty text body and
  /// preview. Fill those in from the stored HTML.
  void _backfillHtmlOnlyText(String accountId) {
    final rows = db.db.select('''
      SELECT m.id, b.html_body FROM messages m JOIN bodies b ON b.message_id = m.id
      WHERE m.account_id = ? AND TRIM(COALESCE(b.text_body, '')) = '' AND b.html_body IS NOT NULL AND b.html_body != ''
    ''', [accountId]);
    for (final r in rows) {
      final text = htmlToText(r['html_body'] as String);
      if (text.isEmpty) continue;
      db.db.execute('UPDATE bodies SET text_body = ? WHERE message_id = ?', [text, r['id']]);
      db.db.execute('UPDATE messages SET snippet = ? WHERE id = ?', [text.length > 160 ? text.substring(0, 160) : text, r['id']]);
    }
  }

  void _purgeLegacyUidRows(String accountId) {
    final key = 'uid_sync_v2_$accountId';
    final done = db.db.select('SELECT 1 FROM settings WHERE key = ?', [key]);
    if (done.isNotEmpty) return;
    db.db.execute('DELETE FROM bodies WHERE message_id IN (SELECT id FROM messages WHERE account_id = ?)', [accountId]);
    db.db.execute('DELETE FROM messages WHERE account_id = ?', [accountId]);
    db.db.execute("INSERT OR REPLACE INTO settings (key, value) VALUES (?, '1')", [key]);
  }

  Future<void> _syncFolderMessages(
    String accountId,
    String folderId,
    String serverPath,
    ImapFolderInfo? junkFolder,
  ) async {
    await imap.selectMailbox(serverPath);
    final row = db.db.select(
      'SELECT MAX(uid) as max_uid FROM messages WHERE folder_id = ?',
      [folderId],
    );
    final int lastUid = (row.firstOrNull?['max_uid'] as int?) ?? 0;

    final fetched = lastUid == 0
        ? await imap.fetchRecent(count: initialFetchCount)
        : await imap.fetchNewerThan(lastUid);
    logInfo('sync', '$serverPath: fetched ${fetched.length} messages (lastUid $lastUid)');
    // Newest first, so the top of the list fills in before older mail.
    final messages = [...fetched]..sort((a, b) => (b.uid ?? 0).compareTo(a.uid ?? 0));
    var processed = 0;
    for (final msg in messages) {
      final uid = msg.uid ?? 0;
      if (uid == 0) continue;
      final msgId = '${folderId}_$uid';
      final subject = msg.decodeSubject() ?? '(No subject)';
      final sender = msg.from?.firstOrNull?.email ?? 'unknown@example.com';
      final senderDomain = sender.contains('@') ? sender.split('@').last : null;
      final recipients = (msg.to?.map((a) => a.email).whereType<String>() ?? const []).join(', ');
      final date = msg.decodeDate() ?? DateTime.now();
      final rawHtml = msg.decodeTextHtmlPart();
      var snippet = (msg.decodeTextPlainPart() ?? '').trim();
      if (snippet.isEmpty && rawHtml != null) snippet = htmlToText(rawHtml);
      final messageIdHeader = msg.getHeaderValue('message-id');

      final sanitized = rawHtml != null
          ? HtmlSanitizer.sanitize(rawHtml, blockRemoteImages: true)
          : null;

      db.db.execute('''
        INSERT OR REPLACE INTO messages
        (id, account_id, folder_id, uid, message_id, subject, sender, sender_domain, recipient_addrs, date, snippet, is_read, has_attachments, classification_label, spam_score)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''', [
        msgId,
        accountId,
        folderId,
        uid,
        messageIdHeader,
        subject,
        sender,
        senderDomain,
        recipients,
        date.toIso8601String(),
        snippet.length > 160 ? snippet.substring(0, 160) : snippet,
        msg.isSeen ? 1 : 0,
        msg.hasAttachments() ? 1 : 0,
        'inbox',
        0.0,
      ]);

      db.db.execute('''
        INSERT OR REPLACE INTO bodies (message_id, text_body, html_body, sanitized_html, remote_images_blocked)
        VALUES (?, ?, ?, ?, ?)
      ''', [
        msgId,
        snippet,
        rawHtml,
        sanitized?.html,
        sanitized?.hasRemoteImages == true ? 1 : 0,
      ]);

      if (filterService != null) {
        final headersMap = <String, List<String>>{};
        for (final h in msg.headers ?? <Header>[]) {
          final val = h.value;
          if (val != null) {
            headersMap.putIfAbsent(h.name, () => []).add(val);
          }
        }
        headersMap.putIfAbsent('From', () => []).add(sender);
        headersMap.putIfAbsent('Subject', () => []).add(subject);

        final toList = msg.to?.map((a) => a.email).whereType<String>().toList() ?? const [];
        final spamMsg = sc.Message(
          headers: headersMap,
          textBody: snippet,
          htmlBody: rawHtml,
          recipientAddrs: toList,
        );

        final verdict = await filterService!.classifyMessage(
          messageId: msgId,
          message: spamMsg,
        );

        if (verdict.spamScore >= 0.9) {
          if (junkFolder != null) {
            try {
              await ImapFlagsManager.markSpam(imap, uid);
              await imap.moveMessage(uid, junkFolder.serverPath);
              final junkFolderId = '${accountId}_${junkFolder.serverPath}';
              db.db.execute(
                'UPDATE messages SET folder_id = ?, classification_label = ? WHERE id = ?',
                [junkFolderId, sc.Label.spam.name, msgId],
              );
            } catch (e, st) {
              logError('move spam $msgId', e, st);
            }
          } else {
            db.db.execute(
              'UPDATE messages SET classification_label = ? WHERE id = ?',
              [sc.Label.spam.name, msgId],
            );
          }
        } else if (verdict.spamScore >= 0.6) {
          db.db.execute(
            'UPDATE messages SET classification_label = ? WHERE id = ?',
            [sc.Label.spam.name, msgId],
          );
        }
      }
      if (++processed % 10 == 0) onChanged?.call();
    }
    onChanged?.call();
    logInfo('sync', '$serverPath: stored ${messages.length} messages');
  }

  Future<void> _processPendingImapActions(AccountRecord account) async {
    final actions = db.db.select(
      'SELECT * FROM pending_imap_actions WHERE account_id = ?',
      [account.id],
    );

    for (final act in actions) {
      final id = act['id'] as int;
      final uid = act['uid'] as int;
      final actionType = act['action'] as String;
      final targetFolder = act['target_folder'] as String?;
      try {
        if (actionType == 'mark_spam') {
          await ImapFlagsManager.markSpam(imap, uid);
          if (targetFolder != null) {
            await imap.moveMessage(uid, targetFolder);
          }
        } else if (actionType == 'mark_ham') {
          await ImapFlagsManager.markHam(imap, uid);
          if (targetFolder != null) {
            await imap.moveMessage(uid, targetFolder);
          }
        } else if (actionType == 'mark_newsletter') {
          await ImapFlagsManager.markNewsletter(imap, uid, serverSupportsPermanentFlags: true);
        }
        db.db.execute('DELETE FROM pending_imap_actions WHERE id = ?', [id]);
      } catch (e, st) {
        logError('pending imap action $id', e, st);
      }
    }
  }
}

final syncEngineProvider = Provider<SyncEngine>((ref) {
  final db = ref.watch(databaseProvider);
  final repo = ref.watch(accountRepositoryProvider);
  final filterService = ref.watch(filterServiceProvider);
  return SyncEngine(
    db: db,
    accountRepo: repo,
    filterService: filterService,
    onChanged: () => ref.read(mailRevisionProvider.notifier).bump(),
  );
});
