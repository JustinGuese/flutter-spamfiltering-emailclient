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

    test('anti-poisoning applies to synced mail when htmlBody has hidden-styled element', () {
      const hiddenPart = 'secretpoisonword buyviagranow';
      final msg = const Message(
        headers: {'from': ['newsletter@store.com'], 'subject': ['Weekly Deals']},
        textBody: 'Special deals for you today. $hiddenPart Check them out.',
        htmlBody: '<p>Special deals for you today. <span style="display:none">$hiddenPart</span> Check them out.</p>',
      );

      final normalized = Normalizer.normalize(msg);
      final tokens = Tokenizer.tokens(normalized);

      expect(normalized.cleanedText, contains('secretpoisonword'));
      expect(tokens, contains('special'));
      expect(tokens, contains('deals'));
      expect(tokens, isNot(contains('secretpoisonword')));
      expect(tokens, isNot(contains('buyviagranow')));
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

    test('tracks messageTotals and addMessages', () async {
      final store = MemoryTokenStore();
      expect(await store.messageTotals(), equals((spam: 0, ham: 0)));

      store.addMessages(Label.spam, 5);
      store.addMessages(Label.ham, 10);
      store.addMessages(Label.newsletter, 2);
      expect(await store.messageTotals(), equals((spam: 5, ham: 12)));

      store.addMessages(Label.spam, -2);
      expect(await store.messageTotals(), equals((spam: 3, ham: 12)));

      // Clamp at 0
      store.addMessages(Label.spam, -10);
      expect(await store.messageTotals(), equals((spam: 0, ham: 12)));

      // Alias
      final aliasStore = InMemoryTokenStore(null, 2, 4);
      expect(await aliasStore.messageTotals(), equals((spam: 2, ham: 4)));
    });
  });

  group('Contracts', () {
    test('Message attachmentNames and replyTo', () {
      const msg = Message(
        headers: {
          'Reply-To': ['replies@example.com'],
        },
        textBody: 'Hello',
        attachmentNames: ['invoice.pdf'],
      );
      expect(msg.attachmentNames, equals(['invoice.pdf']));
      expect(msg.replyTo, equals('replies@example.com'));

      const emptyMsg = Message(headers: {}, textBody: '');
      expect(emptyMsg.attachmentNames, isEmpty);
      expect(emptyMsg.replyTo, isNull);
    });

    test('Signals knownContact and senderRule', () {
      const signals = Signals(
        knownContact: true,
        senderRule: SenderRuleAction.allow,
      );
      expect(signals.knownContact, isTrue);
      expect(signals.senderRule, equals(SenderRuleAction.allow));
    });

    test('Verdict isPhishing', () {
      const nonPhish = Verdict(
        label: Label.spam,
        spamScore: 0.9,
        evidence: [
          Evidence(id: 'bayes', weight: 0.8, detail: 'bayes match'),
        ],
      );
      expect(nonPhish.isPhishing, isFalse);

      for (final id in phishingEvidenceIds) {
        final phish = Verdict(
          label: Label.spam,
          spamScore: 0.95,
          evidence: [
            Evidence(id: id, weight: 0.5, detail: 'test'),
          ],
        );
        expect(phish.isPhishing, isTrue, reason: '$id should be detected as phishing');
      }
    });
  });
}
