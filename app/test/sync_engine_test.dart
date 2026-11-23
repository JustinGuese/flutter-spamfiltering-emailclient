import 'dart:async';
import 'dart:io';
import 'package:sqlite3/sqlite3.dart';
import 'package:spamfiltering_emailclient/db/database.dart';
import 'package:spamfiltering_emailclient/mail/account_repository.dart';
import 'package:spamfiltering_emailclient/mail/imap_service.dart';
import 'package:spamfiltering_emailclient/mail/mail_auth.dart';
import 'package:spamfiltering_emailclient/mail/sync_engine.dart';
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
    return Mailbox(encodedName: path, encodedPath: path, pathSeparator: '/', flags: []);
  }

  @override
  Future<List<MimeMessage>> fetchRecent({int count = 100}) async {
    recentCalls++;
    return inbox;
  }

  @override
  Future<List<MimeMessage>> fetchNewerThan(int lastUid) async {
    newerThan = lastUid;
    return const [];
  }

  @override
  Future<void> disconnect() async => disconnected = true;
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
      ..execute('CREATE TABLE messages (id TEXT PRIMARY KEY, recipient_addrs TEXT NOT NULL)')
      ..execute("INSERT INTO messages VALUES ('m1', 'x@y.z')");
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
}
