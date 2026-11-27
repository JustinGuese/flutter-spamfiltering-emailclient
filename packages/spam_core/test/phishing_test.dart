import 'package:test/test.dart';
import 'package:spam_core/spam_core.dart';

void main() {
  group('Phishing and Anti-poisoning (S3)', () {
    late MemoryTokenStore store;

    setUp(() {
      store = MemoryTokenStore();
    });

    test('paypa1.com sender claiming PayPal -> lookalike_domain + isPhishing', () async {
      final msg = const Message(
        headers: {
          'from': ['PayPal Security <support@paypa1.com>'],
          'subject': ['Your account has been limited'],
        },
        textBody: 'Please update your details.',
      );
      final norm = Normalizer.normalize(msg);
      final verdict = await Classifier.score(norm, store);

      expect(verdict.evidence.any((e) => e.id == 'lookalike_domain'), isTrue);
      expect(verdict.isPhishing, isTrue);
    });

    test('real paypal.com sender -> no phishing evidence', () async {
      final msg = const Message(
        headers: {
          'from': ['PayPal <service@paypal.com>'],
          'subject': ['Receipt for your payment'],
        },
        textBody: 'Thank you for your business.',
      );
      final norm = Normalizer.normalize(msg);
      final verdict = await Classifier.score(norm, store);

      expect(verdict.isPhishing, isFalse);
      expect(verdict.evidence.any((e) => phishingEvidenceIds.contains(e.id)), isFalse);
    });

    test('invoice.pdf.exe -> dangerous_attachment', () async {
      final msg = const Message(
        headers: {
          'from': ['accounting@company.com'],
          'subject': ['Invoice overdue'],
        },
        textBody: 'Please find attached invoice.',
        attachmentNames: ['invoice.pdf.exe'],
      );
      final norm = Normalizer.normalize(msg);
      final verdict = await Classifier.score(norm, store);

      expect(verdict.evidence.any((e) => e.id == 'dangerous_attachment'), isTrue);
      expect(verdict.isPhishing, isTrue);
    });

    test('newsletter whose Reply-To is a different corporate domain -> no reply_to_mismatch', () async {
      final msg = const Message(
        headers: {
          'from': ['updates@substack.com'],
          'reply-to': ['author@mycompany.org'],
          'subject': ['Issue #42'],
        },
        textBody: 'Here is the weekly update.',
      );
      final norm = Normalizer.normalize(msg);
      final verdict = await Classifier.score(norm, store);

      expect(verdict.evidence.any((e) => e.id == 'reply_to_mismatch'), isFalse);
    });

    test('reply_to_mismatch fires when Reply-To is freemail', () async {
      final msg = const Message(
        headers: {
          'from': ['Support <support@mybank.com>'],
          'reply-to': ['Bank Support <bankservice@gmail.com>'],
          'subject': ['Urgent update'],
        },
        textBody: 'Please reply to confirm your identity.',
      );
      final norm = Normalizer.normalize(msg);
      final verdict = await Classifier.score(norm, store);

      expect(verdict.evidence.any((e) => e.id == 'reply_to_mismatch'), isTrue);
      expect(verdict.isPhishing, isTrue);
    });

    test('punycode domain in link host -> punycode_domain + isPhishing', () async {
      final msg = const Message(
        headers: {
          'from': ['info@news.com'],
          'subject': ['Click here'],
        },
        textBody: 'Visit https://xn--pple-43d.com for rewards',
      );
      final norm = Normalizer.normalize(msg);
      final verdict = await Classifier.score(norm, store);

      expect(verdict.evidence.any((e) => e.id == 'punycode_domain'), isTrue);
      expect(verdict.isPhishing, isTrue);
    });

    test('hidden-span text does not appear in tokens', () {
      final msg = const Message(
        headers: {'from': ['sender@example.com'], 'subject': ['Special offer']},
        textBody: '',
        htmlBody: '<p>Visible legitimate text <span style="display:none">hiddenhamword poisonsignal</span></p>',
      );
      final norm = Normalizer.normalize(msg);
      final tokens = Tokenizer.tokens(norm);

      expect(tokens, contains('visible'));
      expect(tokens, contains('legitimate'));
      expect(tokens, isNot(contains('hiddenhamword')));
      expect(tokens, isNot(contains('poisonsignal')));
    });

    test('zero-width characters are stripped from tokens', () {
      final msg = const Message(
        headers: {'from': ['sender@example.com'], 'subject': ['Special offer']},
        textBody: 'free\u200Bmoney\uFEFFnow',
      );
      final norm = Normalizer.normalize(msg);
      final tokens = Tokenizer.tokens(norm);

      expect(tokens, contains('freemoneynow'));
    });

    test('URL shortener adds url_shortener evidence without being phishing', () async {
      final msg = const Message(
        headers: {
          'from': ['announcements@example.com'],
          'subject': ['Quick link'],
        },
        textBody: 'Check this link: https://bit.ly/3XYZ123 for our presentation.',
      );
      final norm = Normalizer.normalize(msg);
      final verdict = await Classifier.score(norm, store);

      expect(verdict.evidence.any((e) => e.id == 'url_shortener'), isTrue);
      expect(verdict.isPhishing, isFalse);
    });
  });
}
