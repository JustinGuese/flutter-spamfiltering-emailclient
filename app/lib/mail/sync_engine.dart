import 'dart:io';
import 'package:enough_mail/enough_mail.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spam_core/spam_core.dart' as sc;
import '../db/database.dart';
import '../search/search_query.dart';
import '../filter/filter_service.dart';
import '../filter/imap_flags.dart';
import '../notifications/notify_types.dart';
import '../notifications/new_mail_notifier.dart';
import 'account_repository.dart';
import '../app/log.dart';
import 'attachments.dart';
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
  final void Function(List<NewMail>)? onNewMail;
  final AttachmentCache attachmentCache;

  SyncEngine({
    required this.db,
    required this.accountRepo,
    ImapService? imap,
    this.filterService,
    this.onChanged,
    this.onNewMail,
    AttachmentCache? attachmentCache,
  })  : imap = imap ?? ImapService(),
        attachmentCache = attachmentCache ?? AttachmentCache();

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
        // Aliases of mail that lives elsewhere: never listed, never synced.
        if (folder.specialUse == 'virtual') continue;
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

        final isSent = folder.specialUse == 'sent';
        final isInbox = folder.specialUse == 'inbox';
        if (isInbox || folder.specialUse == null || isSent) {
          try {
            await _syncFolderMessages(
              account.id,
              folderId,
              folder.serverPath,
              junkFolder,
              classify: !isSent,
              isInbox: isInbox,
            );
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
    db.db.execute('DELETE FROM attachments WHERE message_id IN (SELECT id FROM messages WHERE account_id = ?)', [accountId]);
    db.db.execute('DELETE FROM messages WHERE account_id = ?', [accountId]);
    db.db.execute("INSERT OR REPLACE INTO settings (key, value) VALUES (?, '1')", [key]);
  }

  Future<void> _syncFolderMessages(
    String accountId,
    String folderId,
    String serverPath,
    ImapFolderInfo? junkFolder, {
    // False for Sent: your own outgoing mail is never scored, never moved to
    // Junk and never trains the filter.
    bool classify = true,
    bool isInbox = false,
  }) async {
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
    final newlyNotifiable = <NewMail>[];

    for (final msg in messages) {
      final uid = msg.uid ?? 0;
      if (uid == 0) continue;
      final stored = _storeMessage(accountId, folderId, msg);
      final msgId = stored.id;
      final subject = stored.subject;
      final sender = stored.sender;
      final snippet = stored.text;
      final rawHtml = stored.rawHtml;

      var finalLabel = 'inbox';
      var finalSpamScore = 0.0;

      if (classify && filterService != null) {
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
        finalLabel = verdict.label.name;
        finalSpamScore = verdict.spamScore;

        if (verdict.spamScore >= 0.9) {
          finalLabel = sc.Label.spam.name;
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
          finalLabel = sc.Label.spam.name;
          db.db.execute(
            'UPDATE messages SET classification_label = ? WHERE id = ?',
            [sc.Label.spam.name, msgId],
          );
        }
      }

      if (isInbox &&
          lastUid > 0 &&
          !msg.isSeen &&
          (finalLabel == 'inbox' || finalLabel == 'ham') &&
          finalSpamScore < 0.6) {
        newlyNotifiable.add(
          NewMail(
            messageId: msgId,
            accountId: accountId,
            sender: sender,
            subject: subject,
            receivedAt: stored.date,
          ),
        );
      }

      if (++processed % 10 == 0) onChanged?.call();
    }
    if (newlyNotifiable.isNotEmpty) {
      onNewMail?.call(newlyNotifiable);
    }
    onChanged?.call();
    logInfo('sync', '$serverPath: stored ${messages.length} messages');
  }

  /// Writes one fetched message (and its body) to SQLite, replacing any copy.
  /// Shared by sync and remote search so a message is stored the same way
  /// whichever found it.
  ({String id, String subject, String sender, DateTime date, String text, String? rawHtml}) _storeMessage(
    String accountId,
    String folderId,
    MimeMessage msg,
  ) {
    final uid = msg.uid ?? 0;
    final msgId = '${folderId}_$uid';
    final subject = msg.decodeSubject() ?? '(No subject)';
    final sender = msg.from?.firstOrNull?.email ?? 'unknown@example.com';
    final senderDomain = sender.contains('@') ? sender.split('@').last : null;
    final recipients = (msg.to?.map((a) => a.email).whereType<String>() ?? const []).join(', ');
    final ccAddrs = (msg.cc?.map((a) => a.email).whereType<String>() ?? const []).join(', ');
    final date = msg.decodeDate() ?? DateTime.now();
    final rawHtml = msg.decodeTextHtmlPart();
    var snippet = (msg.decodeTextPlainPart() ?? '').trim();
    if (snippet.isEmpty && rawHtml != null) snippet = htmlToText(rawHtml);
    final messageIdHeader = msg.getHeaderValue('message-id');

    final sanitized = rawHtml != null ? HtmlSanitizer.sanitize(rawHtml, blockRemoteImages: true) : null;
    final files = extractAttachments(msg);

    final headersMap = <String, List<String>>{};
    for (final h in msg.headers ?? <Header>[]) {
      final val = h.value;
      if (val != null) {
        headersMap.putIfAbsent(h.name, () => []).add(val);
      }
    }
    final listUnsubHeaders = [
      for (final h in msg.headers ?? <Header>[])
        if (h.name.toLowerCase() == 'list-unsubscribe' && h.value != null)
          h.value!
    ];
    final listUnsubscribe = listUnsubHeaders.isNotEmpty
        ? listUnsubHeaders.join(', ')
        : msg.getHeaderValue('list-unsubscribe');
    final listUnsubscribePost = msg.getHeaderValue('list-unsubscribe-post');

    final authResults = sc.AuthResults.parse(headersMap);
    final senderAuthPass = (authResults.dmarc == sc.AuthVerdict.pass ||
            authResults.dkim == sc.AuthVerdict.pass)
        ? 1
        : 0;

    db.db.execute('''
      INSERT OR REPLACE INTO messages
      (id, account_id, folder_id, uid, message_id, subject, sender, sender_domain, recipient_addrs, cc_addrs, date, snippet, is_read, has_attachments, classification_label, spam_score, list_unsubscribe, list_unsubscribe_post, sender_auth_pass)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
      ccAddrs,
      date.toIso8601String(),
      snippet.length > 160 ? snippet.substring(0, 160) : snippet,
      msg.isSeen ? 1 : 0,
      files.isEmpty ? 0 : 1,
      'inbox',
      0.0,
      listUnsubscribe,
      listUnsubscribePost,
      senderAuthPass,
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
    _storeAttachmentRows(msgId, files);
    return (id: msgId, subject: subject, sender: sender, date: date, text: snippet, rawHtml: rawHtml);
  }

  /// Records which files a message carries (names and part numbers only; the
  /// bytes stay on the server until opened). Rows are left alone when they
  /// already match, so a row id held by an open forward draft stays valid.
  void _storeAttachmentRows(String messageId, List<AttachmentMeta> files) {
    final current = db.db
        .select('SELECT fetch_id, filename FROM attachments WHERE message_id = ? ORDER BY id', [messageId])
        .map((r) => '${r['fetch_id']}|${r['filename']}')
        .toList();
    if (current.join('\n') == files.map((f) => '${f.fetchId}|${f.fileName}').join('\n')) return;
    db.db.execute('DELETE FROM attachments WHERE message_id = ?', [messageId]);
    for (final f in files) {
      db.db.execute(
        'INSERT INTO attachments (message_id, fetch_id, filename, mime_type, size) VALUES (?, ?, ?, ?, ?)',
        [messageId, f.fetchId, f.fileName, f.mimeType, f.size],
      );
    }
  }

  // ---- Attachments -----------------------------------------------------------

  /// The attachments of a stored message. Mail synced before attachments were
  /// listed has none recorded; those are filled in from the server here, once.
  Future<List<AttachmentMeta>> attachmentsOf(String messageId) {
    final rows = _attachmentRows(messageId);
    if (rows.isNotEmpty) return Future.value(rows);
    final flagged = db.db.select('SELECT has_attachments FROM messages WHERE id = ?', [messageId]);
    if (flagged.isEmpty || flagged.first['has_attachments'] != 1) return Future.value(const []);
    // Block body on purpose, as in syncAccount: callers asking while one is running share it.
    return _backfilling[messageId] ??= _backfillAttachments(messageId).whenComplete(() {
      _backfilling.remove(messageId);
    });
  }

  final _backfilling = <String, Future<List<AttachmentMeta>>>{};

  Future<List<AttachmentMeta>> _backfillAttachments(String messageId) async {
    await _withServerCopy(messageId, (msg) async {
      final files = extractAttachments(msg);
      _storeAttachmentRows(messageId, files);
      // Only counted as a file under the older, narrower rule: not a file.
      if (files.isEmpty) db.db.execute('UPDATE messages SET has_attachments = 0 WHERE id = ?', [messageId]);
    });
    onChanged?.call();
    return _attachmentRows(messageId);
  }

  List<AttachmentMeta> _attachmentRows(String messageId) => db.db
      .select('SELECT * FROM attachments WHERE message_id = ? ORDER BY id', [messageId])
      .map((r) => AttachmentMeta(
            id: r['id'] as int,
            fetchId: r['fetch_id'] as String,
            fileName: r['filename'] as String,
            mimeType: r['mime_type'] as String,
            size: r['size'] as int,
          ))
      .toList();

  /// The file for attachment [attachmentId], downloading it from the mail
  /// server on first use and keeping it on the device afterwards.
  Future<File> downloadAttachment(int attachmentId) async {
    final row = db.db.select('''
      SELECT a.*, m.account_id, m.id AS msg_id FROM attachments a
      JOIN messages m ON m.id = a.message_id WHERE a.id = ?
    ''', [attachmentId]).firstOrNull;
    if (row == null) throw StateError('This attachment is no longer available.');
    final meta = AttachmentMeta(
      id: attachmentId,
      fetchId: row['fetch_id'] as String,
      fileName: row['filename'] as String,
      mimeType: row['mime_type'] as String,
      size: row['size'] as int,
    );
    final accountId = row['account_id'] as String;
    final messageId = row['msg_id'] as String;

    final cached = await attachmentCache.find(accountId, messageId, meta);
    if (cached != null) return cached;

    return _withServerCopy(messageId, (msg) async {
      // A concurrent request for the same file may have finished while this one waited.
      final raced = await attachmentCache.find(accountId, messageId, meta);
      if (raced != null) return raced;
      final bytes = partOf(msg, meta.fetchId)?.decodeContentBinary();
      if (bytes == null) throw StateError('The mail server did not return "${meta.fileName}".');
      db.db.execute('UPDATE attachments SET size = ? WHERE id = ?', [bytes.length, attachmentId]);
      return attachmentCache.write(accountId, messageId, meta, bytes);
    });
  }

  /// Runs [job] with a fresh copy of the stored message fetched from its server
  /// folder, on the shared connection.
  ///
  /// The stored UID is not trusted: a message the filter or the user moved to
  /// Junk keeps the UID it had in the old folder, which names nothing or
  /// another message there. The copy must carry the stored `Message-ID`; when
  /// the UID misses, the folder is searched for that header instead.
  Future<T> _withServerCopy<T>(String messageId, Future<T> Function(MimeMessage msg) job) {
    return _enqueue(() async {
      final row = db.db.select('''
        SELECT m.account_id, m.uid, m.message_id, f.server_path
        FROM messages m LEFT JOIN folders f ON f.id = m.folder_id WHERE m.id = ?
      ''', [messageId]).firstOrNull;
      final serverPath = row?['server_path'] as String?;
      if (row == null || serverPath == null) throw StateError('This message is no longer in the local mailbox.');
      final account = accountRepo.listAccounts().where((a) => a.id == row['account_id']).firstOrNull;
      if (account == null) throw StateError('The account of this message was removed.');
      final auth = await accountRepo.getAuthForAccount(account.id);
      if (auth == null) throw StateError('No saved password for ${account.email}.');

      await imap.connectAndAuthenticate(account, auth);
      try {
        await imap.selectMailbox(serverPath);
        final wantedId = (row['message_id'] as String?)?.trim();
        final msg = await _findOnServer(row['uid'] as int, wantedId);
        if (msg == null) throw StateError('This message is no longer on the mail server.');
        return await job(msg);
      } finally {
        try {
          await imap.disconnect();
        } catch (e) {
          logError('imap disconnect', e);
        }
      }
    });
  }

  Future<MimeMessage?> _findOnServer(int uid, String? wantedMessageId) async {
    bool matches(MimeMessage m) =>
        wantedMessageId == null || wantedMessageId.isEmpty || m.getHeaderValue('message-id')?.trim() == wantedMessageId;

    for (final m in await imap.fetchByUids([uid])) {
      if (matches(m)) return m;
    }
    // A header search only works for a plain ASCII id; anything else is not worth quoting.
    if (wantedMessageId == null || !RegExp(r'^[\x21-\x7e]+$').hasMatch(wantedMessageId)) return null;
    final quoted = wantedMessageId.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
    final uids = await imap.searchUids('HEADER MESSAGE-ID "$quoted"');
    if (uids.isEmpty) return null;
    for (final m in await imap.fetchByUids([uids.last])) {
      if (matches(m)) return m;
    }
    return null;
  }

  // ---- Remote search -------------------------------------------------------

  /// How many matches per folder a server search imports (newest first).
  static const remoteHitsPerFolder = 25;

  int _remoteSearchSeq = 0;

  /// Asks every account's mail server to search for [input] and stores the
  /// matches it was missing (mail older than what sync pulled, Archive and
  /// other folders that are not synced), so the normal local search then shows
  /// them. Runs on the same queue and connection as sync. Each account is
  /// synced first: importing a hit newer than the folder's stored UIDs would
  /// otherwise make the next sync skip the mail in between.
  ///
  /// `imported` counts messages stored; `failed` counts accounts that could not
  /// be searched (offline, bad login) and `error` is the first reason. A newer call supersedes an older one
  /// that has not started its server round-trip yet.
  Future<({int imported, int failed, String? error})> searchRemote(String input) async {
    final q = parseSearch(input);
    if (!q.remoteable || q.imapCriteria.isEmpty) return (imported: 0, failed: 0, error: null);
    final seq = ++_remoteSearchSeq;
    var imported = 0;
    var failed = 0;
    String? error;
    for (final account in accountRepo.listAccounts()) {
      if (seq != _remoteSearchSeq) break;
      try {
        await syncAccount(account.id);
        imported += await _enqueue(() => seq == _remoteSearchSeq ? _searchAccount(account, q.imapCriteria) : Future.value(0));
      } catch (e, st) {
        failed++;
        error ??= e is StateError ? e.message : e.toString(); // shown to the user
        logError('remote search ${account.email}', e, st);
      }
    }
    return (imported: imported, failed: failed, error: error);
  }

  Future<T> _enqueue<T>(Future<T> Function() job) {
    final run = _queue.catchError((Object _) {}).then((_) => job());
    _queue = run.then<void>((_) {}, onError: (Object _) {});
    return run;
  }

  Future<int> _searchAccount(AccountRecord account, String criteria) async {
    final auth = await accountRepo.getAuthForAccount(account.id);
    if (auth == null) throw StateError('No saved password for ${account.email}.');
    await imap.connectAndAuthenticate(account, auth);
    var imported = 0;
    try {
      for (final folder in await imap.listSpecialUseFolders()) {
        // Spam and Trash are skipped: imported mail is not scored, so it would
        // come back looking like ordinary inbox mail.
        const skipped = {'virtual', 'junk', 'trash', 'drafts'};
        if (!folder.selectable || skipped.contains(folder.specialUse)) continue;
        final folderId = '${account.id}_${folder.serverPath}';
        final folderRow = db.db.select('SELECT 1 FROM folders WHERE id = ?', [folderId]);
        if (folderRow.isEmpty) continue;
        try {
          imported += await _importHits(account.id, folderId, folder, criteria);
        } catch (e, st) {
          logError('remote search ${folder.serverPath}', e, st); // one folder must not stop the rest
        }
      }
    } finally {
      try {
        await imap.disconnect();
      } catch (e) {
        logError('imap disconnect', e);
      }
    }
    if (imported > 0) onChanged?.call();
    return imported;
  }

  Future<int> _importHits(String accountId, String folderId, ImapFolderInfo folder, String criteria) async {
    await imap.selectMailbox(folder.serverPath);
    final found = await imap.searchUids(criteria);
    if (found.isEmpty) return 0;

    // Folders that sync keeps current only take mail at or below the newest
    // UID already stored, or the next sync would skip what lies between.
    final synced = folder.specialUse == 'inbox' || folder.specialUse == null || folder.specialUse == 'sent';
    final maxUid = (db.db.select('SELECT MAX(uid) AS u FROM messages WHERE folder_id = ?', [folderId]).first['u'] as int?) ?? 0;
    final stored = db.db
        .select('SELECT uid FROM messages WHERE folder_id = ?', [folderId])
        .map((r) => r['uid'] as int)
        .toSet();
    final wanted = (found.where((u) => !stored.contains(u) && (!synced || u <= maxUid)).toList()
          ..sort((a, b) => b.compareTo(a)))
        .take(remoteHitsPerFolder)
        .toList();

    var n = 0;
    for (final msg in await imap.fetchByUids(wanted)) {
      if ((msg.uid ?? 0) == 0) continue;
      _storeMessage(accountId, folderId, msg);
      n++;
    }
    return n;
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
  final mailNotifier = ref.watch(newMailNotifierProvider);
  return SyncEngine(
    db: db,
    accountRepo: repo,
    filterService: filterService,
    onChanged: () => ref.read(mailRevisionProvider.notifier).bump(),
    onNewMail: (batch) => mailNotifier.add(batch),
    attachmentCache: ref.watch(attachmentCacheProvider),
  );
});
