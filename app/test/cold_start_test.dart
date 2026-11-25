import 'package:flutter_test/flutter_test.dart';
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
}
