import 'dart:io';

import 'package:enough_mail/enough_mail.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spam_core/spam_core.dart';
import 'package:spamfiltering_emailclient/db/database.dart';
import 'package:spamfiltering_emailclient/filter/token_store_drift.dart';

/// Gate on the bundled `assets/prior_model.json`: it is all a fresh install
/// scores with until it has learned from the user's own mail, so it must not
/// send modern legitimate mail to Junk. (A SpamAssassin-trained prior failed
/// this: its 2002 mailing-list ham made receipts and bills look like spam.)
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bundled prior alone never auto-moves the synthetic ham fixtures', () async {
    final db = await AppDatabase.open(inMemory: true);
    final store = TokenStoreDrift(db);
    await store.seedPriorModelIfEmpty();
    expect(store.totalTrainedTokens(), greaterThan(0), reason: 'prior must seed');

    final dir = Directory('../packages/spam_core/test/fixtures/eval/ham');
    final files = dir.listSync().whereType<File>().toList();
    expect(files.length, greaterThanOrEqualTo(30));

    var flagged = 0;
    final autoMoved = <String>[];
    for (final f in files) {
      final mime = MimeMessage.parseFromText(f.readAsStringSync());
      final headers = <String, List<String>>{};
      for (final h in mime.headers ?? const <Header>[]) {
        final v = h.value;
        if (v != null) headers.putIfAbsent(h.name, () => []).add(v);
      }
      final verdict = await Classifier.score(
        Normalizer.normalize(Message(
          headers: headers,
          textBody: (mime.decodeTextPlainPart() ?? '').trim(),
          htmlBody: mime.decodeTextHtmlPart(),
        )),
        store,
      );
      if (verdict.spamScore >= 0.9) autoMoved.add(f.uri.pathSegments.last);
      if (verdict.spamScore >= 0.6) flagged++;
    }

    expect(autoMoved, isEmpty, reason: 'ham the prior alone would move to Junk');
    expect(flagged / files.length, lessThanOrEqualTo(0.05));
  });
}
