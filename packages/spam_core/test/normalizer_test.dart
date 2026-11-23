import 'package:test/test.dart';
import 'package:spam_core/spam_core.dart';

void main() {
  group('Normalizer', () {
    test('strips greeting lines and recipient addresses/names', () {
      final msg = Message(
        headers: {
          'to': ['Alice Smith <alice@example.com>'],
          'from': ['partner@vendor.com'],
        },
        textBody: '''
Hi Alice Smith,
We have completed processing your annual account summary for alice@example.com.
Thanks for choosing our service.
''',
        recipientAddrs: ['alice@example.com'],
      );

      final normalized = Normalizer.normalize(msg);
      expect(normalized.cleanedText.contains('hi alice smith'), isFalse);
      expect(normalized.cleanedText.contains('alice@example.com'), isFalse);
      expect(normalized.cleanedText.contains('alice'), isFalse);
    });

    test('strips HTML tags and extracts URLs', () {
      final msg = Message(
        headers: {'from': ['info@service.org']},
        textBody: '',
        htmlBody: '''
<html>
  <body>
    <h1>Security Notice</h1>
    <p>Please log in <a href="https://service.org/login?session=abc#top">here</a> to verify.</p>
  </body>
</html>
''',
      );

      final normalized = Normalizer.normalize(msg);
      expect(normalized.cleanedText, contains('security notice'));
      expect(normalized.cleanedText, isNot(contains('<html>')));
      expect(normalized.extractedUrls, contains('https://service.org/login'));
    });
  });

  group('Tokenizer', () {
    test('generates body words, OSB bigrams, and prefixed header tokens', () {
      final msg = Message(
        headers: {
          'subject': ['Quarterly Earnings Report'],
          'from': ['cfo@investor-relations.com'],
          'list-unsubscribe': ['<mailto:unsub@investor.com>'],
        },
        textBody: 'The quarterly financial results are now available for investor review.',
      );

      final normalized = Normalizer.normalize(msg);
      final tokens = Tokenizer.tokens(normalized);

      // Body words
      expect(tokens, contains('quarterly'));
      expect(tokens, contains('financial'));

      // OSB bigrams
      expect(tokens, contains('quarterly+financial'));

      // Prefixed headers
      expect(tokens, contains('subj:quarterly'));
      expect(tokens, contains('subj:earnings'));
      expect(tokens, contains('from-dom:investor-relations.com'));
      expect(tokens, contains('list-unsub:present'));
    });
  });

  group('MemoryTokenStore', () {
    test('tracks and applies counts per label', () async {
      final store = MemoryTokenStore();
      const hash = 998877;

      expect((await store.counts(hash)).spam, equals(0));

      await store.apply(hash, Label.spam, 3);
      await store.apply(hash, Label.ham, 1);
      await store.apply(hash, Label.newsletter, 5);

      final counts = await store.counts(hash);
      expect(counts.spam, equals(3));
      expect(counts.ham, equals(1));
      expect(counts.newsletter, equals(5));
      expect(counts.inbox, equals(0));

      // Decrement / un-train
      await store.apply(hash, Label.spam, -1);
      expect((await store.counts(hash)).spam, equals(2));
    });
  });
}
