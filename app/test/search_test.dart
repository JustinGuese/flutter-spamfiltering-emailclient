import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:spamfiltering_emailclient/db/database.dart';
import 'package:spamfiltering_emailclient/search/search_query.dart';
import 'package:spamfiltering_emailclient/search/search_service.dart';

void _add(
  AppDatabase db,
  String id, {
  required String subject,
  String sender = 'a@example.com',
  String to = 'me@example.com',
  String body = '',
  String date = '2026-11-01T10:00:00',
  String label = 'inbox',
  bool read = true,
  bool attachment = false,
}) {
  db.db.execute('''
    INSERT OR REPLACE INTO messages
    (id, account_id, folder_id, uid, subject, sender, sender_domain, recipient_addrs, cc_addrs, date, snippet, is_read, has_attachments, classification_label)
    VALUES (?, 'acc', 'f', 1, ?, ?, 'example.com', ?, '', ?, ?, ?, ?, ?)
  ''', [id, subject, sender, to, date, body, read ? 1 : 0, attachment ? 1 : 0, label]);
  db.db.execute('INSERT OR REPLACE INTO bodies (message_id, text_body) VALUES (?, ?)', [id, body]);
}

List<String> _ids(AppDatabase db, String q, {bool spam = false}) =>
    searchMessages(db, q, includeSpam: spam).map((m) => m.id).toList();

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(sqlite3.openInMemory()));
  tearDown(() => db.close());

  group('parseSearch', () {
    test('plain words become ANDed prefix terms', () {
      expect(parseSearch('hello wor').match, '"hello" * AND "wor" *');
    });
    test('quoted text is an exact phrase', () {
      expect(parseSearch('"quarterly report"').match, '"quarterly report"');
    });
    test('operators map to columns and filters', () {
      final q = parseSearch('from:bob@x.com is:unread after:2026-01-01');
      expect(q.match, '(sender : "bob x com" *)');
      expect(q.where, ['m.is_read = 0', 'm.date >= ?']);
      expect(q.args, ['2026-01-01']);
    });
    test('maps to IMAP SEARCH criteria for the server', () {
      expect(parseSearch('invoice amazon').imapCriteria, 'TEXT "invoice" TEXT "amazon"');
      expect(parseSearch('"quarterly report"').imapCriteria, 'TEXT "quarterly report"');
      expect(parseSearch('from:bob subject:hi is:unread').imapCriteria, 'FROM "bob" SUBJECT "hi" UNSEEN');
      expect(parseSearch('after:2026-01-05 before:2026-12-31').imapCriteria, 'SINCE 5-Jan-2026 BEFORE 31-Dec-2026');
      expect(parseSearch('x has:attachment').imapCriteria, 'TEXT "x"'); // IMAP cannot; filtered locally
      expect(parseSearch('cheap is:spam').remoteable, isFalse);
      expect(parseSearch('say "hi" \\ done').imapCriteria, 'TEXT "say" TEXT "hi" TEXT "done"');
    });
    test('unknown operators and junk fall back to text, never throw', () {
      expect(parseSearch('foo:bar').match, '"foo bar" *');
      expect(parseSearch('is:nonsense').match, '"is nonsense" *');
      expect(parseSearch('") ( * OR NOT').match, isNotNull);
      expect(parseSearch('   ').isEmpty, isTrue);
      expect(parseSearch('!!!').isEmpty, isTrue);
    });
  });

  group('searchMessages', () {
    test('matches subject, sender, recipient and body; prefixes as you type', () {
      _add(db, '1', subject: 'Invoice 4711', body: 'please pay');
      _add(db, '2', subject: 'Lunch', sender: 'amazon@shop.com', body: 'sandwich');
      _add(db, '3', subject: 'Hi', to: 'zebra@zoo.org', body: 'the quarterly report is attached');
      expect(_ids(db, 'invo'), ['1']);
      expect(_ids(db, 'amazon'), ['2']);
      expect(_ids(db, 'zebra'), ['3']);
      expect(_ids(db, 'quarterly report'), ['3']);
      expect(_ids(db, 'nothing here'), isEmpty);
    });

    test('ranks subject hits above body hits', () {
      _add(db, 'body', subject: 'Hello', body: 'about the budget', date: '2026-11-05T10:00:00');
      _add(db, 'subj', subject: 'Budget', body: 'hello', date: '2026-11-01T10:00:00');
      expect(_ids(db, 'budget'), ['subj', 'body']);
    });

    test('operators filter', () {
      _add(db, 'u', subject: 'Deal', sender: 'bob@shop.com', read: false);
      _add(db, 'r', subject: 'Deal', sender: 'amy@shop.com', attachment: true);
      expect(_ids(db, 'deal is:unread'), ['u']);
      expect(_ids(db, 'deal from:amy'), ['r']);
      expect(_ids(db, 'deal has:attachment'), ['r']);
      expect(_ids(db, 'is:unread'), ['u']); // filters alone work
      expect(_ids(db, 'deal after:2026-12-01'), isEmpty);
      expect(_ids(db, 'deal before:2026-12-01').length, 2);
    });

    test('spam is hidden unless asked for', () {
      _add(db, 's', subject: 'Cheap pills', label: 'spam');
      _add(db, 'h', subject: 'Cheap flights');
      expect(_ids(db, 'cheap'), ['h']);
      expect(_ids(db, 'cheap', spam: true).toSet(), {'s', 'h'});
      expect(_ids(db, 'cheap is:spam'), ['s']);
    });

    test('index follows replaced, updated and deleted bodies', () {
      _add(db, 'x', subject: 'Old news', body: 'alpha');
      _add(db, 'x', subject: 'Old news', body: 'beta'); // INSERT OR REPLACE, like sync
      expect(_ids(db, 'alpha'), isEmpty);
      expect(_ids(db, 'beta'), ['x']);
      db.db.execute("UPDATE bodies SET text_body = 'gamma' WHERE message_id = 'x'");
      expect(_ids(db, 'beta'), isEmpty);
      expect(_ids(db, 'gamma'), ['x']);
      db.db.execute("DELETE FROM bodies WHERE message_id = 'x'");
      expect(_ids(db, 'gamma'), isEmpty);
    });

    test('backfills mail that existed before the index', () {
      final old = sqlite3.openInMemory();
      final first = AppDatabase(old);
      _add(first, 'o', subject: 'Legacy mail', body: 'ancient text');
      old.execute('DROP TRIGGER search_index_ai; DROP TRIGGER search_index_au; DROP TRIGGER search_index_ad; DROP TABLE search_index;');
      final migrated = AppDatabase(old);
      expect(_ids(migrated, 'ancient'), ['o']);
    });

    test('hostile input never throws', () {
      _add(db, 'a', subject: 'x');
      for (final q in ['"', '(', ')*', 'AND', 'NOT', 'a OR', 'col:x', '\'']) {
        expect(() => searchMessages(db, q), returnsNormally);
      }
    });
  });
}
