import 'dart:async';
import 'dart:io';
import 'package:sqlite3/sqlite3.dart';
import 'package:spamfiltering_emailclient/db/database.dart';
import 'package:spamfiltering_emailclient/filter/filter_service.dart';
import 'package:spamfiltering_emailclient/filter/token_store_drift.dart';
import 'package:spamfiltering_emailclient/mail/account_repository.dart';
import 'package:spamfiltering_emailclient/mail/imap_service.dart';
import 'package:spamfiltering_emailclient/mail/mail_auth.dart';
import 'package:spamfiltering_emailclient/mail/sync_engine.dart';
import 'package:spamfiltering_emailclient/notifications/notify_types.dart';
import 'package:spam_core/spam_core.dart' as sc;
import 'package:enough_mail/enough_mail.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeStorage implements FlutterSecureStorage {
  @override
  Future<String?> read({required String key, dynamic iOptions, dynamic aOptions, dynamic lOptions, dynamic webOptions, dynamic mOptions, dynamic wOptions}) async =>
      key.startsWith('auth_pass_') ? 'pw' : null;

  @override
  Future<void> delete({required String key, dynamic iOptions, dynamic aOptions, dynamic lOptions, dynamic webOptions, dynamic mOptions, dynamic wOptions}) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _NoPasswordStorage extends _FakeStorage {
  @override
  Future<String?> read({required String key, dynamic iOptions, dynamic aOptions, dynamic lOptions, dynamic webOptions, dynamic mOptions, dynamic wOptions}) async => null;
}

MimeMessage _msg(int uid, int seq) => MimeMessage()
  ..uid = uid
  ..sequenceId = seq
  ..addHeader('Subject', 'Mail $uid')
  ..addHeader('From', 'sender$uid@example.com')
  ..addHeader('Date', 'Mon, 02 Nov 2026 10:00:00 +0000');

class _FakeImap extends ImapService {
  final selected = <String>[];
  var recentCalls = 0;
  var connects = 0;
  int? newerThan;
  var disconnected = false;
  final List<MimeMessage> inbox;
  List<ImapFolderInfo>? folders;
  _FakeImap(this.inbox);

  @override
  Future<void> connectAndAuthenticate(AccountRecord account, MailAuth auth, {Duration timeout = const Duration(seconds: 20)}) async {
    connects++;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }

  @override
  Future<List<ImapFolderInfo>> listSpecialUseFolders() async => folders ?? const [
        ImapFolderInfo(name: '[Gmail]', serverPath: '[Gmail]', selectable: false),
        ImapFolderInfo(name: 'INBOX', serverPath: 'INBOX', specialUse: 'inbox'),
        ImapFolderInfo(name: 'All Mail', serverPath: '[Gmail]/All Mail', specialUse: 'virtual'),
      ];

  @override
  Future<Mailbox> selectMailbox(String path) async {
    selected.add(path);
    current = path;
    return Mailbox(encodedName: path, encodedPath: path, pathSeparator: '/', flags: []);
  }

  @override
  Future<List<MimeMessage>> fetchRecent({int count = 100}) async {
    recentCalls++;
    return inbox;
  }

  List<MimeMessage> newerMessages = const [];

  @override
  Future<List<MimeMessage>> fetchNewerThan(int lastUid) async {
    newerThan = lastUid;
    return newerMessages;
  }

  String? current;
  final hitsByFolder = <String, List<int>>{};
  final criteriaSeen = <String>[];
  final fetchedUids = <String, List<int>>{};

  @override
  Future<List<int>> searchUids(String criteria) async {
    criteriaSeen.add(criteria);
    return hitsByFolder[current] ?? const [];
  }

  @override
  Future<List<MimeMessage>> fetchByUids(List<int> uids) async {
    fetchedUids[current!] = uids;
    return [for (final u in uids) _msg(u, u)];
  }

  @override
  Future<void> disconnect() async => disconnected = true;
}

class _FakeFilterService extends FilterService {
  final sc.Verdict Function(String messageId, sc.Message msg)? onClassify;

  _FakeFilterService(AppDatabase db, {this.onClassify})
      : super(
          db: db,
          tokenStore: TokenStoreDrift(db),
        );

  @override
  Future<sc.Verdict> classifyMessage({
    required String messageId,
    required sc.Message message,
    bool isCommunityMatch = false,
  }) async {
    if (onClassify != null) {
      return onClassify!(messageId, message);
    }
    return const sc.Verdict(label: sc.Label.inbox, spamScore: 0.1);
  }
}

void main() {
  late AppDatabase db;
  late AccountRepository repo;

  setUp(() {
    db = AppDatabase(sqlite3.openInMemory());
    repo = AccountRepository(db: db, storage: _FakeStorage());
    db.db.execute(
      "INSERT INTO accounts (id, email, display_name, imap_host, imap_port, smtp_host, smtp_port, auth_type, created_at) "
      "VALUES ('a1', 'me@gmail.com', 'me', 'imap.gmail.com', 993, 'smtp.gmail.com', 587, 'password', '2026-01-01T00:00:00Z')",
    );
  });

  test('first sync stores the fetched inbox by real UID, skips Noselect and virtual folders', () async {
    final imap = _FakeImap([_msg(9001, 1), _msg(9002, 2), _msg(9003, 3)]);
    var changes = 0;
    final engine = SyncEngine(db: db, accountRepo: repo, imap: imap, onChanged: () => changes++);

    await engine.syncAccount('a1');

    expect(imap.selected, ['INBOX']);
    expect(imap.recentCalls, 1);
    expect(imap.disconnected, isTrue);
    expect(changes, greaterThan(0));
    final uids = db.db
        .select('SELECT uid FROM messages WHERE account_id = ? ORDER BY uid', ['a1'])
        .map((r) => r['uid'])
        .toList();
    expect(uids, [9001, 9002, 9003]);
    final folders = db.db.select('SELECT name FROM folders').map((r) => r['name']).toList();
    expect(folders, isNot(contains('[Gmail]')));
  });

  test('Sent is listed and its mail stored, but never classified or moved to Junk', () async {
    final sentImap = _FakeImap([_msg(7001, 1)])
      ..folders = const [
        ImapFolderInfo(name: 'Sent Mail', serverPath: '[Gmail]/Sent Mail', specialUse: 'sent'),
        ImapFolderInfo(name: 'All Mail', serverPath: '[Gmail]/All Mail', specialUse: 'virtual'),
      ];
    await SyncEngine(db: db, accountRepo: repo, imap: sentImap).syncAccount('a1');

    expect(sentImap.selected, ['[Gmail]/Sent Mail']);
    final folders = db.db.select('SELECT name FROM folders').map((r) => r['name']).toList();
    expect(folders, ['Sent Mail'], reason: 'virtual folders are not listed');
    expect(db.db.select('SELECT uid FROM messages').map((r) => r['uid']).toList(), [7001]);
  });

  test('Cc addresses are stored for Reply All', () async {
    final m = _msg(8001, 1)..addHeader('Cc', 'carol@x.com, dave@x.com');
    await SyncEngine(db: db, accountRepo: repo, imap: _FakeImap([m])).syncAccount('a1');
    final cc = db.db.select('SELECT cc_addrs FROM messages').first['cc_addrs'];
    expect(cc, contains('carol@x.com'));
    expect(cc, contains('dave@x.com'));
  });

  test('an existing messages table without cc_addrs is migrated', () {
    final old = sqlite3.openInMemory()
      ..execute('CREATE TABLE messages (id TEXT PRIMARY KEY, subject TEXT, sender TEXT, recipient_addrs TEXT NOT NULL)')
      ..execute("INSERT INTO messages (id, recipient_addrs) VALUES ('m1', 'x@y.z')");
    final migrated = AppDatabase(old);
    expect(migrated.db.select('SELECT cc_addrs FROM messages').first['cc_addrs'], '');
  });

  test('later syncs ask only for UIDs above the highest stored one', () async {
    final imap = _FakeImap([_msg(9001, 1), _msg(9002, 2)]);
    final engine = SyncEngine(db: db, accountRepo: repo, imap: imap);
    await engine.syncAccount('a1');
    await engine.syncAccount('a1');

    expect(imap.recentCalls, 1);
    expect(imap.newerThan, 9002);
  });

  test('rows cached by the old sequence-number sync are dropped once', () async {
    db.db.execute(
      "INSERT INTO folders (id, account_id, name, server_path, special_use, unread_count) VALUES ('a1_INBOX','a1','INBOX','INBOX','inbox',0)",
    );
    db.db.execute(
      "INSERT INTO messages (id, account_id, folder_id, uid, subject, sender, recipient_addrs, date, snippet, is_read, has_attachments) "
      "VALUES ('a1_INBOX_30','a1','a1_INBOX',30,'old','x@y.z','','2005-01-01T00:00:00','',0,0)",
    );
    final imap = _FakeImap([_msg(9001, 1)]);
    await SyncEngine(db: db, accountRepo: repo, imap: imap).syncAccount('a1');

    expect(imap.recentCalls, 1, reason: 'stale max uid must not block the first real fetch');
    final uids = db.db.select('SELECT uid FROM messages').map((r) => r['uid']).toList();
    expect(uids, [9001]);
  });

  test('deleting an account removes its folders, messages and cache but not others', () async {
    await SyncEngine(db: db, accountRepo: repo, imap: _FakeImap([_msg(9001, 1), _msg(9002, 2)])).syncAccount('a1');
    db.db.execute(
      "INSERT INTO accounts (id, email, display_name, imap_host, imap_port, smtp_host, smtp_port, auth_type, created_at) "
      "VALUES ('a2', 'other@x.com', 'o', 'h', 993, 'h', 587, 'password', '2026-01-01T00:00:00Z')",
    );
    expect(db.db.select('SELECT 1 FROM messages WHERE account_id = ?', ['a1']), isNotEmpty);

    await repo.deleteAccount('a1');

    int count(String table, String where) => db.db.select('SELECT COUNT(*) c FROM $table WHERE $where').first['c'] as int;
    expect(count('accounts', "id = 'a1'"), 0);
    expect(count('messages', "account_id = 'a1'"), 0);
    expect(count('folders', "account_id = 'a1'"), 0);
    expect(count('bodies', '1=1'), 0);
    expect(count('accounts', "id = 'a2'"), 1);
  });

  test('concurrent syncs of one account share a single connection run', () async {
    final imap = _FakeImap([_msg(9001, 1)]);
    final engine = SyncEngine(db: db, accountRepo: repo, imap: imap);
    await Future.wait([engine.syncAccount('a1'), engine.syncAccount('a1')]);
    expect(imap.connects, 1);
  });

  test('connecting to a server that never speaks IMAP times out instead of hanging', () async {
    // Like pointing IMAP at an SMTP host: the socket opens but no IMAP greeting comes.
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final held = <Socket>[];
    server.listen(held.add);
    addTearDown(() async {
      for (final c in held) {
        c.destroy();
      }
      await server.close();
    });
    final account = AccountRecord(
      id: 'x', email: 'me@x.com', displayName: 'me',
      imapHost: '127.0.0.1', imapPort: server.port,
      smtpHost: 'h', smtpPort: 587, authType: 'password', createdAt: DateTime.now(),
    );
    await expectLater(
      ImapService().connectAndAuthenticate(account, PasswordMailAuth('pw'), timeout: const Duration(seconds: 1)),
      throwsA(isA<TimeoutException>()),
    );
  });

  group('remote search', () {
    final folders = const [
      ImapFolderInfo(name: 'INBOX', serverPath: 'INBOX', specialUse: 'inbox'),
      ImapFolderInfo(name: 'Archive', serverPath: 'Archive', specialUse: 'archive'),
      ImapFolderInfo(name: 'Junk', serverPath: 'Junk', specialUse: 'junk'),
      ImapFolderInfo(name: 'All Mail', serverPath: '[Gmail]/All Mail', specialUse: 'virtual'),
    ];

    test('imports older and unsynced-folder hits, skips stored, newer-than-synced, junk and virtual', () async {
      final imap = _FakeImap([_msg(9001, 1), _msg(9002, 2)])..folders = folders;
      final engine = SyncEngine(db: db, accountRepo: repo, imap: imap);
      await engine.syncAccount('a1'); // stores 9001, 9002; creates folder rows

      imap.hitsByFolder['INBOX'] = [9001, 5000, 9999]; // stored, old, newer than synced
      imap.hitsByFolder['Archive'] = [12];
      imap.hitsByFolder['Junk'] = [77];
      imap.selected.clear();
      final r = await engine.searchRemote('invoice from:amazon');

      expect(r, (imported: 2, failed: 0, error: null));
      expect(imap.criteriaSeen, everyElement('TEXT "invoice" FROM "amazon"'));
      expect(imap.fetchedUids['INBOX'], [5000]);
      expect(imap.fetchedUids['Archive'], [12]);
      // The sync that runs first selects the Inbox; the search then covers Inbox and Archive.
      expect(imap.selected, ['INBOX', 'INBOX', 'Archive'], reason: 'Junk and virtual folders are not searched');
      final ids = db.db.select('SELECT id FROM messages').map((r) => r['id']).toSet();
      expect(ids, containsAll(['a1_INBOX_5000', 'a1_Archive_12']));
      expect(ids, isNot(contains('a1_INBOX_9999')));
      // Imported mail is findable by the local index afterwards.
      expect(db.db.select("SELECT 1 FROM search_index WHERE search_index MATCH 'Mail'").length, greaterThanOrEqualTo(4));
      expect(imap.disconnected, isTrue);
    });

    test('caps the import per folder, newest first', () async {
      final imap = _FakeImap([_msg(9001, 1)])..folders = folders;
      final engine = SyncEngine(db: db, accountRepo: repo, imap: imap);
      await engine.syncAccount('a1');
      imap.hitsByFolder['Archive'] = [for (var i = 1; i <= 40; i++) i];
      await engine.searchRemote('mail');
      expect(imap.fetchedUids['Archive'], [for (var i = 40; i > 15; i--) i]);
    });

    test('queries only the device knows (is:spam) never reach the server', () async {
      final imap = _FakeImap([_msg(9001, 1)])..folders = folders;
      final engine = SyncEngine(db: db, accountRepo: repo, imap: imap);
      await engine.syncAccount('a1');
      final before = imap.connects;
      expect(await engine.searchRemote('is:spam cheap'), (imported: 0, failed: 0, error: null));
      expect(await engine.searchRemote('   '), (imported: 0, failed: 0, error: null));
      expect(imap.connects, before);
    });

    test('an unreachable account is reported, not swallowed', () async {
      final imap = _FakeImap([_msg(9001, 1)])..folders = folders;
      final engine = SyncEngine(db: db, accountRepo: repo, imap: imap);
      db.db.execute("DELETE FROM accounts"); // nothing to search
      expect(await engine.searchRemote('x'), (imported: 0, failed: 0, error: null));
      db.db.execute(
        "INSERT INTO accounts (id, email, display_name, imap_host, imap_port, smtp_host, smtp_port, auth_type, created_at) "
        "VALUES ('a2', 'b@x.com', 'b', 'h', 993, 's', 587, 'password', '2026-01-01T00:00:00Z')",
      );
      final failing = SyncEngine(db: db, accountRepo: AccountRepository(db: db, storage: _NoPasswordStorage()), imap: imap);
      final failed = await failing.searchRemote('x');
      expect((failed.imported, failed.failed), (0, 1));
      expect(failed.error, contains('No saved password'), reason: 'the reason reaches the UI');
    });
  });

  group('onNewMail notifications', () {
    test('onNewMail fires only for new unread classified-inbox mail, not on initial fetch, not twice', () async {
      final initialMsgs = [_msg(9001, 1), _msg(9002, 2)];
      final imap = _FakeImap(initialMsgs);
      final filterService = _FakeFilterService(db);

      final newMailBatches = <List<NewMail>>[];
      final engine = SyncEngine(
        db: db,
        accountRepo: repo,
        imap: imap,
        filterService: filterService,
        onNewMail: (batch) => newMailBatches.add(batch),
      );

      // 1. Initial fetch: 2 unread messages in inbox. Must NOT fire onNewMail!
      await engine.syncAccount('a1');
      expect(newMailBatches, isEmpty, reason: 'Initial fetch must not fire notifications');

      // 2. Second sync: same messages, no new messages.
      await engine.syncAccount('a1');
      expect(newMailBatches, isEmpty, reason: 'No new mail fetched');

      // 3. New fetch with:
      // - 9003: unread, inbox verdict (spamScore 0.1) -> should notify
      // - 9004: read (isSeen: true), inbox verdict -> should NOT notify
      // - 9005: unread, spam verdict (spamScore 0.95) -> should NOT notify
      // - 9006: unread, newsletter verdict -> should NOT notify
      // - 9007: unread, unsure-junk (spamScore 0.7) -> should NOT notify
      final msgSeen = _msg(9004, 4)..flags = [r'\Seen'];
      imap.newerMessages = [
        _msg(9003, 3),
        msgSeen,
        _msg(9005, 5),
        _msg(9006, 6),
        _msg(9007, 7),
      ];

      final classifyingFilter = _FakeFilterService(db, onClassify: (msgId, msg) {
        if (msgId.endsWith('_9003')) {
          return const sc.Verdict(label: sc.Label.inbox, spamScore: 0.1);
        } else if (msgId.endsWith('_9004')) {
          return const sc.Verdict(label: sc.Label.inbox, spamScore: 0.1);
        } else if (msgId.endsWith('_9005')) {
          return const sc.Verdict(label: sc.Label.spam, spamScore: 0.95);
        } else if (msgId.endsWith('_9006')) {
          return const sc.Verdict(label: sc.Label.newsletter, spamScore: 0.2);
        } else if (msgId.endsWith('_9007')) {
          return const sc.Verdict(label: sc.Label.spam, spamScore: 0.7);
        }
        return const sc.Verdict(label: sc.Label.inbox, spamScore: 0.1);
      });

      final engineWithClassifier = SyncEngine(
        db: db,
        accountRepo: repo,
        imap: imap,
        filterService: classifyingFilter,
        onNewMail: (batch) => newMailBatches.add(batch),
      );

      await engineWithClassifier.syncAccount('a1');

      expect(newMailBatches.length, 1);
      final batch = newMailBatches.first;
      expect(batch.length, 1, reason: 'Only 9003 meets all criteria');
      expect(batch.first.messageId, 'a1_INBOX_9003');
      expect(batch.first.accountId, 'a1');
      expect(batch.first.sender, 'sender9003@example.com');
      expect(batch.first.subject, 'Mail 9003');

      // 4. Third sync: ensure it doesn't fire twice for the same mail
      newMailBatches.clear();
      imap.newerMessages = [];
      await engineWithClassifier.syncAccount('a1');
      expect(newMailBatches, isEmpty, reason: 'Must not fire twice');
    });

    test('non-inbox folders (Sent, etc.) never notify', () async {
      final imap = _FakeImap([_msg(1001, 1)])
        ..folders = const [
          ImapFolderInfo(name: 'Sent Mail', serverPath: '[Gmail]/Sent Mail', specialUse: 'sent'),
        ];
      final newMailBatches = <List<NewMail>>[];
      final engine = SyncEngine(
        db: db,
        accountRepo: repo,
        imap: imap,
        onNewMail: (batch) => newMailBatches.add(batch),
      );

      // Initial sync
      await engine.syncAccount('a1');
      expect(newMailBatches, isEmpty);

      // New sent mail
      imap.newerMessages = [_msg(1002, 2)];
      await engine.syncAccount('a1');
      expect(newMailBatches, isEmpty, reason: 'Sent folder must never notify');
    });
  });
}
