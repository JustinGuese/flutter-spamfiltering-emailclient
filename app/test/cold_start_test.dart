import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:spam_core/spam_core.dart';
import 'package:spamfiltering_emailclient/db/database.dart';
import 'package:spamfiltering_emailclient/filter/cold_start.dart';
import 'package:spamfiltering_emailclient/filter/token_store_drift.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Junk training runs once, not on every launch', () async {
    final db = await AppDatabase.open(inMemory: true);
    db.db.execute(
        "INSERT INTO folders (id, account_id, name, server_path, special_use) VALUES ('junk', 'a', 'Junk', 'Junk', 'junk')");
    db.db.execute('''
      INSERT INTO messages (id, account_id, folder_id, uid, subject, sender,
        recipient_addrs, date, snippet)
      VALUES ('m1', 'a', 'junk', 1, 'win a free prize now', 'x@spam.test',
        'me@example.com', '2026-01-01T00:00:00Z', '')
    ''');
    final store = TokenStoreDrift(db);
    final trainer = ColdStartTrainer(db: db, tokenStore: store);

    await trainer.runColdStart();
    final afterFirst = store.totalTrainedTokens();
    expect(afterFirst, greaterThan(0));

    await trainer.runColdStart();
    await trainer.runColdStart();
    expect(store.totalTrainedTokens(), afterFirst);
  });

  test('an inbox of read normal mail + a junk folder balanced cold start', () async {
    final db = await AppDatabase.open(inMemory: true);
    db.db.execute(
        "INSERT INTO folders (id, account_id, name, server_path, special_use) VALUES ('junk', 'a', 'Junk', 'Junk', 'junk')");
    db.db.execute(
        "INSERT INTO folders (id, account_id, name, server_path, special_use) VALUES ('inbox', 'a', 'Inbox', 'INBOX', 'inbox')");

    // Junk message with overlapping words
    db.db.execute('''
      INSERT INTO messages (id, account_id, folder_id, uid, subject, sender,
        recipient_addrs, date, snippet, is_read, spam_score)
      VALUES ('j1', 'a', 'junk', 1, 'project update invoice schedule', 'spam@test.com',
        'me@example.com', '2026-01-01T00:00:00Z', '', 0, 0.9)
    ''');
    db.db.execute('''
      INSERT INTO bodies (message_id, text_body)
      VALUES ('j1', 'urgent project update schedule invoice meeting details')
    ''');

    // Inbox messages with overlapping words (enough to pass the ham minimum)
    _insertReadInbox(db, 25);

    final store = TokenStoreDrift(db);
    final trainer = ColdStartTrainer(db: db, tokenStore: store);

    await trainer.runColdStart();

    final hamTotalFirst = int.parse(db.getSetting('msg_total_ham') ?? '0');
    final spamTotalFirst = int.parse(db.getSetting('msg_total_spam') ?? '0');
    // Totals = the bundled prior's totals (if any) + what cold start trained (25 ham, 1 spam).
    final prior = jsonDecode(File('assets/prior_model.json').readAsStringSync()) as Map<String, dynamic>;
    expect(hamTotalFirst, equals(((prior['total_ham'] as num?)?.toInt() ?? 0) + 25));
    expect(spamTotalFirst, equals(((prior['total_spam'] as num?)?.toInt() ?? 0) + 1));

    // Fresh normal message whose words appear in both is NOT scored >= 0.6
    final freshMsg = Message(
      headers: {
        'From': ['client@example.com'],
        'Subject': ['project update schedule'],
      },
      textBody: 'project update schedule meeting details',
    );
    final verdict = await Classifier.score(Normalizer.normalize(freshMsg), store);
    expect(verdict.spamScore, lessThan(0.6));

    // Running cold start twice does not double ham counts
    await trainer.runColdStart();
    final hamTotalSecond = int.parse(db.getSetting('msg_total_ham') ?? '0');
    expect(hamTotalSecond, equals(hamTotalFirst));
  });

  test('ham training waits for enough read mail instead of marking itself done', () async {
    final db = await AppDatabase.open(inMemory: true);
    db.db.execute(
        "INSERT INTO folders (id, account_id, name, server_path, special_use) VALUES ('inbox', 'a', 'Inbox', 'INBOX', 'inbox')");
    final store = TokenStoreDrift(db);
    final trainer = ColdStartTrainer(db: db, tokenStore: store);

    // Fresh install: launch-time cold start on an empty mailbox trains nothing...
    await trainer.runColdStart();
    expect(db.getSetting('cold_start_ham_trained'), isNot('1'));

    // ...and the run after the first sync, once mail is there, does.
    _insertReadInbox(db, ColdStartTrainer.minHamMessages + 5);
    await trainer.runColdStart();
    expect(db.getSetting('cold_start_ham_trained'), '1');
    expect(int.parse(db.getSetting('msg_total_ham')!), ColdStartTrainer.minHamMessages + 5);
  });

  test('totals are backfilled from token counts on installs that trained before totals existed', () async {
    final db = await AppDatabase.open(inMemory: true);
    final store = TokenStoreDrift(db);
    // 40 spam and 12 ham messages trained the old way: counts, no totals.
    for (var i = 0; i < 40; i++) {
      for (final t in Tokenizer.tokens(Normalizer.normalize(Message(
          headers: {'From': ['s$i@spam.test'], 'Subject': ['cheap pills $i']}, textBody: 'cheap pills offer $i')))) {
        store.apply(Tokenizer.hashToken(t), Label.spam, 1);
      }
    }
    for (var i = 0; i < 12; i++) {
      for (final t in Tokenizer.tokens(Normalizer.normalize(Message(
          headers: {'From': ['c$i@example.com'], 'Subject': ['meeting notes $i']}, textBody: 'meeting notes for the team $i')))) {
        store.apply(Tokenizer.hashToken(t), Label.ham, 1);
      }
    }
    await ColdStartTrainer(db: db, tokenStore: store).runColdStart();
    final totals = await store.messageTotals();
    expect(totals.spam, 40);
    expect(totals.ham, 12);
  });
}

void _insertReadInbox(AppDatabase db, int n) {
  for (var i = 1; i <= n; i++) {
    final date = DateTime.utc(2026, 1, 2).add(Duration(minutes: i)).toIso8601String();
    db.db.execute('''
      INSERT INTO messages (id, account_id, folder_id, uid, subject, sender,
        recipient_addrs, date, snippet, is_read, spam_score)
      VALUES (?, 'a', 'inbox', ?, 'project update schedule', ?, 'me@example.com', ?, '', 1, 0.0)
    ''', ['m$i', 100 + i, 'colleague$i@example.com', date]);
    db.db.execute(
      'INSERT INTO bodies (message_id, text_body) VALUES (?, ?)',
      ['m$i', 'project update schedule invoice meeting details for team discussion'],
    );
  }
}
