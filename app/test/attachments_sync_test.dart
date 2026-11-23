import 'dart:io';
import 'dart:typed_data';
import 'package:enough_mail/enough_mail.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spamfiltering_emailclient/db/database.dart';
import 'package:spamfiltering_emailclient/mail/account_repository.dart';
import 'package:spamfiltering_emailclient/mail/attachments.dart';
import 'package:spamfiltering_emailclient/mail/imap_service.dart';
import 'package:spamfiltering_emailclient/mail/mail_auth.dart';
import 'package:spamfiltering_emailclient/mail/smtp_service.dart';
import 'package:spamfiltering_emailclient/mail/sync_engine.dart';
import 'package:sqlite3/sqlite3.dart';

class _Storage implements FlutterSecureStorage {
  @override
  Future<String?> read({required String key, dynamic iOptions, dynamic aOptions, dynamic lOptions, dynamic webOptions, dynamic mOptions, dynamic wOptions}) async =>
      key.startsWith('auth_pass_') ? 'pw' : null;
  @override
  Future<void> delete({required String key, dynamic iOptions, dynamic aOptions, dynamic lOptions, dynamic webOptions, dynamic mOptions, dynamic wOptions}) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// A server whose mail is a uid -> message map per folder.
class _Server extends ImapService {
  final folderMail = <String, Map<int, MimeMessage>>{};
  var current = '';
  final fetches = <String>[]; // "folder:uid"
  final searches = <String>[];

  @override
  Future<void> connectAndAuthenticate(AccountRecord account, MailAuth auth, {Duration timeout = const Duration(seconds: 20)}) async {}
  @override
  Future<List<ImapFolderInfo>> listSpecialUseFolders() async => const [
        ImapFolderInfo(name: 'INBOX', serverPath: 'INBOX', specialUse: 'inbox'),
        ImapFolderInfo(name: 'Junk', serverPath: 'Junk', specialUse: 'junk'),
      ];
  @override
  Future<Mailbox> selectMailbox(String path) async {
    current = path;
    return Mailbox(encodedName: path, encodedPath: path, pathSeparator: '/', flags: []);
  }

  @override
  Future<List<MimeMessage>> fetchRecent({int count = 100}) async => (folderMail[current] ?? {}).values.toList();
  @override
  Future<List<MimeMessage>> fetchNewerThan(int lastUid) async => const [];
  @override
  Future<List<MimeMessage>> fetchByUids(List<int> uids) async {
    final out = <MimeMessage>[];
    for (final u in uids) {
      fetches.add('$current:$u');
      final m = folderMail[current]?[u];
      if (m != null) out.add(m);
    }
    return out;
  }

  @override
  Future<List<int>> searchUids(String criteria) async {
    searches.add(criteria);
    final id = RegExp(r'MESSAGE-ID "(.*)"').firstMatch(criteria)!.group(1)!;
    return [
      for (final e in (folderMail[current] ?? {}).entries)
        if (e.value.getHeaderValue('message-id') == id) e.key,
    ];
  }

  @override
  Future<void> disconnect() async {}
}

MimeMessage _mail(int uid, String messageId, {List<LoadedAttachment> files = const []}) {
  final built = buildOutgoingMessage(
    from: MailAddress('S', 's@example.com'),
    to: ['me@example.com'],
    subject: 'Mail $uid',
    bodyText: 'body $uid',
    attachments: files,
  )
    ..setHeader('Message-ID', messageId)
    ..setHeader('Date', 'Mon, 02 Nov 2026 10:00:00 +0000');
  return MimeMessage.parseFromText(built.renderMessage())..uid = uid;
}

void main() {
  late AppDatabase db;
  late _Server server;
  late SyncEngine engine;
  late Directory cacheDir;
  final pdf = Uint8List.fromList(List.generate(4000, (i) => i % 251));

  setUp(() {
    db = AppDatabase(sqlite3.openInMemory());
    db.db.execute(
      "INSERT INTO accounts (id, email, display_name, imap_host, imap_port, smtp_host, smtp_port, auth_type, created_at) "
      "VALUES ('a1', 'me@example.com', 'me', 'imap.example.com', 993, 'smtp.example.com', 587, 'password', '2026-01-01T00:00:00Z')",
    );
    server = _Server();
    cacheDir = Directory.systemTemp.createTempSync('att_sync');
    engine = SyncEngine(
      db: db,
      accountRepo: AccountRepository(db: db, storage: _Storage()),
      imap: server,
      attachmentCache: AttachmentCache(root: () async => cacheDir),
    );
  });
  tearDown(() => cacheDir.deleteSync(recursive: true));

  Future<void> syncWith(Map<int, MimeMessage> inbox) async {
    server.folderMail['INBOX'] = inbox;
    await engine.syncAccount('a1');
  }

  int attachmentId(String msgId) => db.db.select('SELECT id FROM attachments WHERE message_id = ?', [msgId]).first['id'] as int;

  test('sync records each message\'s files; plain mail has none', () async {
    await syncWith({
      1: _mail(1, '<one@x>', files: [LoadedAttachment('a.pdf', 'application/pdf', pdf), LoadedAttachment('b.png', 'image/png', pdf)]),
      2: _mail(2, '<two@x>'),
    });
    final rows = db.db.select('SELECT filename, mime_type FROM attachments ORDER BY id');
    expect(rows.map((r) => r['filename']), ['a.pdf', 'b.png']);
    expect(db.db.select("SELECT has_attachments FROM messages WHERE id = 'a1_INBOX_1'").first.columnAt(0), 1);
    expect(db.db.select("SELECT has_attachments FROM messages WHERE id = 'a1_INBOX_2'").first.columnAt(0), 0);
  });

  test('a repeated sync keeps the attachment row ids (an open forward draft holds one)', () async {
    final inbox = {1: _mail(1, '<one@x>', files: [LoadedAttachment('a.pdf', 'application/pdf', pdf)])};
    await syncWith(inbox);
    final before = attachmentId('a1_INBOX_1');
    server.folderMail['INBOX'] = inbox;
    await engine.syncAccount('a1');
    expect(attachmentId('a1_INBOX_1'), before);
    expect(db.db.select('SELECT COUNT(*) FROM attachments').first.columnAt(0), 1);
  });

  test('download fetches the message once, returns the exact bytes, then serves from the device', () async {
    await syncWith({1: _mail(1, '<one@x>', files: [LoadedAttachment('a.pdf', 'application/pdf', pdf)])});
    server.fetches.clear();

    final f = await engine.downloadAttachment(attachmentId('a1_INBOX_1'));
    expect(f.readAsBytesSync(), pdf);
    expect(f.path.endsWith('a.pdf'), isTrue);
    expect(server.fetches, ['INBOX:1']);
    expect(db.db.select('SELECT size FROM attachments').first.columnAt(0), pdf.length, reason: 'estimate replaced by the real size');

    final again = await engine.downloadAttachment(attachmentId('a1_INBOX_1'));
    expect(again.path, f.path);
    expect(server.fetches, ['INBOX:1'], reason: 'no second server round trip');
  });

  test('a message moved to Junk keeps its old UID; the download finds it by Message-ID instead', () async {
    await syncWith({7: _mail(7, '<moved@x>', files: [LoadedAttachment('a.pdf', 'application/pdf', pdf)])});
    // The server moved it: it now has another UID in Junk, and UID 7 there is a stranger.
    db.db.execute("UPDATE messages SET folder_id = 'a1_Junk' WHERE id = 'a1_INBOX_7'");
    server.folderMail['Junk'] = {
      7: _mail(7, '<stranger@x>', files: [LoadedAttachment('secret.pdf', 'application/pdf', Uint8List.fromList([9, 9, 9]))]),
      31: _mail(31, '<moved@x>', files: [LoadedAttachment('a.pdf', 'application/pdf', pdf)]),
    };

    final f = await engine.downloadAttachment(attachmentId('a1_INBOX_7'));
    expect(f.readAsBytesSync(), pdf);
    expect(server.searches.single, 'HEADER MESSAGE-ID "<moved@x>"');
  });

  test('never hands out another message\'s bytes: no match on the server is an error and caches nothing', () async {
    await syncWith({7: _mail(7, '<gone@x>', files: [LoadedAttachment('a.pdf', 'application/pdf', pdf)])});
    server.folderMail['INBOX'] = {7: _mail(7, '<stranger@x>', files: [LoadedAttachment('a.pdf', 'application/pdf', Uint8List.fromList([1]))])};
    await expectLater(engine.downloadAttachment(attachmentId('a1_INBOX_7')), throwsA(isA<StateError>()));
    expect(cacheDir.listSync(recursive: true).whereType<File>(), isEmpty);
  });

  test('a Message-ID that is not plain ASCII is never put into a search command', () async {
    await syncWith({7: _mail(7, '<ok@x>', files: [LoadedAttachment('a.pdf', 'application/pdf', pdf)])});
    db.db.execute("UPDATE messages SET message_id = '<a\"b\r\nX@x>' WHERE id = 'a1_INBOX_7'");
    await expectLater(engine.downloadAttachment(attachmentId('a1_INBOX_7')), throwsA(isA<StateError>()));
    expect(server.searches, isEmpty);
  });

  test('mail stored before attachments were listed is filled in from the server on first look', () async {
    await syncWith({1: _mail(1, '<old@x>', files: [LoadedAttachment('a.pdf', 'application/pdf', pdf)])});
    db.db.execute('DELETE FROM attachments'); // as left by an older build
    expect(db.db.select("SELECT has_attachments FROM messages WHERE id = 'a1_INBOX_1'").first.columnAt(0), 1);

    final list = await engine.attachmentsOf('a1_INBOX_1');
    expect(list.map((a) => a.fileName), ['a.pdf']);
    expect(list.single.id, isNotNull);
  });

  test('a message flagged by the old, narrower rule but with no file is cleared, and not refetched again', () async {
    await syncWith({1: _mail(1, '<old@x>')});
    db.db.execute("UPDATE messages SET has_attachments = 1 WHERE id = 'a1_INBOX_1'");
    expect(await engine.attachmentsOf('a1_INBOX_1'), isEmpty);
    expect(db.db.select("SELECT has_attachments FROM messages WHERE id = 'a1_INBOX_1'").first.columnAt(0), 0);
    server.fetches.clear();
    expect(await engine.attachmentsOf('a1_INBOX_1'), isEmpty);
    expect(server.fetches, isEmpty);
  });

  test('removing the account deletes its attachment rows and cached files', () async {
    final cache = AttachmentCache(root: () async => cacheDir);
    final repo = AccountRepository(db: db, storage: _Storage(), attachmentCache: cache);
    await syncWith({1: _mail(1, '<one@x>', files: [LoadedAttachment('a.pdf', 'application/pdf', pdf)])});
    await engine.downloadAttachment(attachmentId('a1_INBOX_1'));
    expect(cacheDir.listSync(recursive: true).whereType<File>(), isNotEmpty);

    await repo.deleteAccount('a1');
    expect(db.db.select('SELECT COUNT(*) FROM attachments').first.columnAt(0), 0);
    expect(cacheDir.listSync(recursive: true).whereType<File>(), isEmpty);
  });
}
