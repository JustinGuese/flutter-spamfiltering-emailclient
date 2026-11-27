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

    // Inbox messages with overlapping words
    for (var i = 1; i <= 10; i++) {
      db.db.execute('''
        INSERT INTO messages (id, account_id, folder_id, uid, subject, sender,
          recipient_addrs, date, snippet, is_read, spam_score)
        VALUES ('m$i', 'a', 'inbox', ${10 + i}, 'project update schedule', 'colleague$i@example.com',
          'me@example.com', '2026-01-02T0$i:00:00Z', '', 1, 0.0)
      ''');
      db.db.execute('''
        INSERT INTO bodies (message_id, text_body)
        VALUES ('m$i', 'project update schedule invoice meeting details for team discussion')
      ''');
    }

    final store = TokenStoreDrift(db);
    final trainer = ColdStartTrainer(db: db, tokenStore: store);

    await trainer.runColdStart();

    final hamTotalFirst = int.parse(db.getSetting('msg_total_ham') ?? '0');
    final spamTotalFirst = int.parse(db.getSetting('msg_total_spam') ?? '0');
    // Totals = the bundled prior's totals + what cold start trained (10 ham, 1 spam).
    final prior = jsonDecode(File('assets/prior_model.json').readAsStringSync()) as Map<String, dynamic>;
    expect(hamTotalFirst, equals((prior['total_ham'] as num).toInt() + 10));
    expect(spamTotalFirst, equals((prior['total_spam'] as num).toInt() + 1));

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
}
