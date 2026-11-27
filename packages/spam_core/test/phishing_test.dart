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

    test('brand-claim matching on ordinary senders produces no brand evidence', () async {
      for (final from in [
        '"Max Mustermann" <max@example.com>',
        '"Marketing Team" <news@example.com>',
        '"Ingrid" <i@example.org>',
      ]) {
        final msg = Message(
          headers: {'from': [from], 'subject': ['Hello']},
          textBody: 'Hi there',
        );
        final norm = Normalizer.normalize(msg);
        final verdict = await Classifier.score(norm, store);
        expect(
          verdict.evidence.any((e) => e.id == 'display_name_brand_spoof'),
          isFalse,
          reason: 'Expected no display_name_brand_spoof for $from',
        );
      }
    });

    test('legit brand sender variants produce no brand evidence', () async {
      for (final from in [
        '"PayPal" <service@paypal.it>',
        '"Facebook" <n@facebookmail.com>',
      ]) {
        final msg = Message(
          headers: {'from': [from], 'subject': ['Notification']},
          textBody: 'Your update',
        );
        final norm = Normalizer.normalize(msg);
        final verdict = await Classifier.score(norm, store);
        expect(
          verdict.evidence.any((e) => e.id == 'display_name_brand_spoof'),
          isFalse,
          reason: 'Expected no display_name_brand_spoof for $from',
        );
      }
    });

    test('brand spoof on freemail produces display_name_brand_spoof', () async {
      final msg = const Message(
        headers: {
          'from': ['"PayPal Support" <help@gmail.com>'],
          'subject': ['Security Alert'],
        },
        textBody: 'Please confirm your identity',
      );
      final norm = Normalizer.normalize(msg);
      final verdict = await Classifier.score(norm, store);
      expect(verdict.evidence.any((e) => e.id == 'display_name_brand_spoof'), isTrue);
    });

    test('lookalike check skips legitimate domains and fires on real lookalikes', () async {
      final safeDomains = [
        'amazon.fr',
        'dpd.de',
        'ubs.com',
        'stream.com',
        'amazonaws.com',
        'googleapis.com',
        'paypal.it',
      ];
      for (final d in safeDomains) {
        final msg = Message(
          headers: {
            'from': ['service@$d'],
            'subject': ['Notice'],
          },
          textBody: 'Visit https://$d/account for details',
        );
        final norm = Normalizer.normalize(msg);
        final verdict = await Classifier.score(norm, store);
        expect(
          verdict.evidence.any((e) => e.id == 'lookalike_domain'),
          isFalse,
          reason: 'Expected no lookalike_domain for $d',
        );
      }

      final lookalikeDomains = [
        'paypa1.com',
        'rnicrosoft.com',
        'arnazon.de',
        'g00gle.com',
        'linkedln.com',
      ];
      for (final d in lookalikeDomains) {
        final msg = Message(
          headers: {
            'from': ['security@$d'],
            'subject': ['Urgent Security Alert'],
          },
          textBody: 'Log in here: https://$d/login',
        );
        final norm = Normalizer.normalize(msg);
        final verdict = await Classifier.score(norm, store);
        expect(
          verdict.evidence.any((e) => e.id == 'lookalike_domain'),
          isTrue,
          reason: 'Expected lookalike_domain for $d',
        );
      }
    });

    test('hidden_text ignores short newsletter preheaders and fires on massive hidden text', () async {
      // 12-word display:none preheader
      final preheaderWords = List.generate(12, (i) => 'word$i').join(' ');
      final newsletter = Message(
        headers: {
          'from': ['news@letter.com'],
          'subject': ['Weekly Roundup'],
        },
        textBody: 'Here is the main text of the newsletter.',
        htmlBody: '<div style="display:none;max-height:0;overflow:hidden">$preheaderWords</div><p>Here is the main text of the newsletter.</p>',
      );
      final normNews = Normalizer.normalize(newsletter);
      final verdictNews = await Classifier.score(normNews, store);
      expect(verdictNews.evidence.any((e) => e.id == 'hidden_text'), isFalse);

      // 60 hidden words
      final spamWords = List.generate(60, (i) => 'hiddenword$i').join(' ');
      final hiddenSpam = Message(
        headers: {
          'from': ['spammer@bad.org'],
          'subject': ['Special Promo'],
        },
        textBody: 'Check this deal.',
        htmlBody: '<div style="display:none">$spamWords</div><p>Check this deal.</p>',
      );
      final normSpam = Normalizer.normalize(hiddenSpam);
      final verdictSpam = await Classifier.score(normSpam, store);
      expect(verdictSpam.evidence.any((e) => e.id == 'hidden_text'), isTrue);
    });

    test('double-extension rule does not flag harmless files but flags dangerous outer extensions', () async {
      final safeMsg = const Message(
        headers: {
          'from': ['colleague@work.com'],
          'subject': ['Files attached'],
        },
        textBody: 'Here are the scans',
        attachmentNames: ['photo.jpg.png', 'scan.pdf.zip'],
      );
      final normSafe = Normalizer.normalize(safeMsg);
      final verdictSafe = await Classifier.score(normSafe, store);
      expect(verdictSafe.evidence.any((e) => e.id == 'dangerous_attachment'), isFalse);

      final dangerousMsg = const Message(
        headers: {
          'from': ['stranger@suspicious.com'],
          'subject': ['Your invoice'],
        },
        textBody: 'See invoice attached',
        attachmentNames: ['invoice.pdf.exe'],
      );
      final normDangerous = Normalizer.normalize(dangerousMsg);
      final verdictDangerous = await Classifier.score(normDangerous, store);
      expect(verdictDangerous.evidence.any((e) => e.id == 'dangerous_attachment'), isTrue);
    });
  });
}
