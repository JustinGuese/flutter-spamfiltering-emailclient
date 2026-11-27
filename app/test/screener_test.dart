import 'package:flutter_test/flutter_test.dart';
import 'package:spam_core/spam_core.dart';
import 'package:spamfiltering_emailclient/db/database.dart';
import 'package:spamfiltering_emailclient/filter/screener.dart';
import 'package:spamfiltering_emailclient/filter/sender_rules.dart';

void main() {
  late AppDatabase db;
  late Screener screener;
  late SenderRules rules;

  setUp(() async {
    db = await AppDatabase.open(inMemory: true);
    screener = Screener(db);
    rules = SenderRules(db);

    // Seed account and standard folders
    db.db.execute("INSERT INTO accounts (id, email, display_name, imap_host, imap_port, smtp_host, smtp_port, created_at) "
        "VALUES ('acc1', 'me@mymail.com', 'Me', 'imap.test', 993, 'smtp.test', 587, '2026-01-01T00:00:00Z')");
    db.db.execute("INSERT INTO folders (id, account_id, name, server_path, special_use) "
        "VALUES ('inbox_f', 'acc1', 'Inbox', 'INBOX', 'inbox')");
    db.db.execute("INSERT INTO folders (id, account_id, name, server_path, special_use) "
        "VALUES ('junk_f', 'acc1', 'Junk', 'Junk', 'junk')");
    db.db.execute("INSERT INTO folders (id, account_id, name, server_path, special_use) "
        "VALUES ('trash_f', 'acc1', 'Trash', 'Trash', 'trash')");
  });

  tearDown(() {
    db.close();
  });

  void insertMsg({
    required String id,
    required String sender,
    String? senderDomain,
    required String date,
    String folderId = 'inbox_f',
    String classificationLabel = 'inbox',
    double spamScore = 0.0,
  }) {
    db.db.execute('''
      INSERT INTO messages (
        id, account_id, folder_id, uid, subject, sender, sender_domain,
        recipient_addrs, date, snippet, classification_label, spam_score
      ) VALUES (?, 'acc1', ?, 1, 'Subject', ?, ?, 'me@mymail.com', ?, 'Snippet', ?, ?)
    ''', [id, folderId, sender, senderDomain, date, classificationLabel, spamScore]);
  }

  group('Screener (S5)', () {
    test('first mail from unknown sender is new', () {
      insertMsg(
        id: 'msg1',
        sender: 'Alice Unknown <alice@unknown.com>',
        senderDomain: 'unknown.com',
        date: '2026-02-01T10:00:00Z',
      );

      expect(screener.isNewSender('msg1'), isTrue);

      final where = screener.newSenderWhereClause(tableAlias: 'messages');
      final rows = db.db.select(
        'SELECT id FROM messages WHERE ${where.sql}',
        where.args,
      );
      expect(rows.map((r) => r['id']), contains('msg1'));
    });

    test('second mail from same sender is not new', () {
      insertMsg(
        id: 'msg1',
        sender: 'Bob <bob@stranger.org>',
        senderDomain: 'stranger.org',
        date: '2026-02-01T10:00:00Z',
      );
      insertMsg(
        id: 'msg2',
        sender: 'bob@stranger.org',
        senderDomain: 'stranger.org',
        date: '2026-02-02T12:00:00Z',
      );

      // First mail remains the new sender message
      expect(screener.isNewSender('msg1'), isTrue);
      // Second mail is from an existing sender
      expect(screener.isNewSender('msg2'), isFalse);
    });

    test('contact is not new', () {
      db.db.execute('''
        INSERT INTO contacts (id, email, name, trust_level)
        VALUES ('c1', 'friend@trusted.com', 'Friend', 1)
      ''');

      insertMsg(
        id: 'msg_contact',
        sender: 'My Friend <friend@trusted.com>',
        senderDomain: 'trusted.com',
        date: '2026-02-01T10:00:00Z',
      );

      expect(screener.isNewSender('msg_contact'), isFalse);
    });

    test('allowed sender is not new', () {
      rules.set('approved@vendor.com', 'address', SenderRuleAction.allow);

      insertMsg(
        id: 'msg_allow',
        sender: 'approved@vendor.com',
        senderDomain: 'vendor.com',
        date: '2026-02-01T10:00:00Z',
      );

      expect(screener.isNewSender('msg_allow'), isFalse);
    });

    test('strict mode hides new sender from the inbox query', () {
      insertMsg(
        id: 'msg_new',
        sender: 'newguy@somewhere.net',
        senderDomain: 'somewhere.net',
        date: '2026-02-01T10:00:00Z',
      );

      final newSenderWhere = screener.newSenderWhereClause(tableAlias: 'messages');

      // Default 'tab' mode: inbox includes the new sender
      expect(screener.getScreenerMode(), equals('tab'));
      final tabInboxRows = db.db.select(
        "SELECT id FROM messages WHERE folder_id = 'inbox_f' AND COALESCE(classification_label, 'inbox') IN ('inbox', 'ham')",
      );
      expect(tabInboxRows.map((r) => r['id']), contains('msg_new'));

      // Strict mode: inbox query excludes new senders
      screener.setScreenerMode('strict');
      expect(screener.getScreenerMode(), equals('strict'));

      final strictInboxRows = db.db.select('''
        SELECT id FROM messages
        WHERE folder_id = 'inbox_f'
          AND COALESCE(classification_label, 'inbox') IN ('inbox', 'ham')
          AND NOT (${newSenderWhere.sql})
      ''', newSenderWhere.args);
      expect(strictInboxRows.map((r) => r['id']), isNot(contains('msg_new')));

      // But still visible in New Senders query
      final newSendersRows = db.db.select('''
        SELECT id FROM messages
        WHERE folder_id = 'inbox_f'
          AND ${newSenderWhere.sql}
      ''', newSenderWhere.args);
      expect(newSendersRows.map((r) => r['id']), contains('msg_new'));
    });
  });
}
