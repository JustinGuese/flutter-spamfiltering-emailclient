import 'package:test/test.dart';
import 'package:spam_core/spam_core.dart';

void main() {
  group('AuthResults', () {
    test('parses standard RFC 8601 Authentication-Results header', () {
      final headers = {
        'authentication-results': [
          'mx.google.com; dkim=pass header.i=@github.com; spf=pass (google.com: domain of support@github.com designates 192.30.252.0 as permitted sender); dmarc=pass (p=REJECT) header.from=github.com',
        ],
      };

      final results = AuthResults.parse(headers, 'mx.google.com');
      expect(results.authservId, equals('mx.google.com'));
      expect(results.dkim, equals(AuthVerdict.pass));
      expect(results.spf, equals(AuthVerdict.pass));
      expect(results.dmarc, equals(AuthVerdict.pass));
    });

    test('parses failing verdicts correctly', () {
      final headers = {
        'authentication-results': [
          'mail.victim.com; dkim=fail; spf=softfail smtp.mailfrom=evil.com; dmarc=fail (p=REJECT)',
        ],
      };

      final results = AuthResults.parse(headers);
      expect(results.dkim, equals(AuthVerdict.fail));
      expect(results.spf, equals(AuthVerdict.softfail));
      expect(results.dmarc, equals(AuthVerdict.fail));
    });

    test('selects matching authservId when multiple headers exist', () {
      final headers = {
        'authentication-results': [
          'intermediate.proxy.com; spf=none',
          'myprovider.org; dkim=pass; spf=pass; dmarc=pass',
        ],
      };

      final results = AuthResults.parse(headers, 'myprovider.org');
      expect(results.authservId, equals('myprovider.org'));
      expect(results.dkim, equals(AuthVerdict.pass));
      expect(results.spf, equals(AuthVerdict.pass));
    });
  });

  group('Classifier', () {
    late MemoryTokenStore store;

    setUp(() async {
      store = MemoryTokenStore();
      // Train a few tokens
      final spamToken = Tokenizer.hashToken('lottery');
      final hamToken = Tokenizer.hashToken('invoice');
      await store.apply(spamToken, Label.spam, 50);
      await store.apply(hamToken, Label.ham, 50);
    });

    test('scores spam message and generates evidence', () async {
      final msg = Message(
        headers: {
          'from': ['scam@spoofed-bank.com'],
          'subject': ['Claim your lottery winnings now'],
          'authentication-results': ['mx.example.com; dmarc=fail; spf=fail'],
        },
        textBody: 'Congratulations! You won the international lottery reward! Claim your payout immediately.',
      );

      final norm = Normalizer.normalize(msg);
      final verdict = await Classifier.score(norm, store);

      expect(verdict.label, equals(Label.spam));
      expect(verdict.spamScore, greaterThanOrEqualTo(0.60));
      expect(verdict.evidence, isNotEmpty);

      // Verify required evidence ids
      final ids = verdict.evidence.map((e) => e.id).toSet();
      expect(ids.contains('bayes'), isTrue);
      expect(ids.contains('auth_dmarc_fail'), isTrue);
    });

    test('scoreWithoutCommunity undoes exactly what the blocklist added', () async {
      final msg = Message(
        headers: {'from': ['a@b.com'], 'subject': ['Claim your lottery winnings now']},
        textBody: 'Claim your payout immediately, lottery reward waiting.',
      );
      final norm = Normalizer.normalize(msg);
      final plain = await Classifier.score(norm, store);
      final flagged = await Classifier.score(norm, store, const Signals(communityBlocklistMatch: true));

      expect(flagged.spamScore, greaterThan(plain.spamScore));
      expect(Classifier.scoreWithoutCommunity(flagged.spamScore), closeTo(plain.spamScore, 1e-6));
    });

    test('scoreWithoutCommunity survives saturated scores', () {
      expect(Classifier.scoreWithoutCommunity(1.0).isFinite, isTrue);
      expect(Classifier.scoreWithoutCommunity(0.0).isFinite, isTrue);
    });

    test('detects stage-B newsletter from headers', () async {
      final msg = Message(
        headers: {
          'from': ['newsletter@techupdates.com'],
          'subject': ['Weekly Technology Briefing #102'],
          'list-unsubscribe': ['<https://techupdates.com/unsub?id=123>'],
          'list-id': ['<digest.techupdates.com>'],
          'precedence': ['bulk'],
          'authentication-results': ['mx.example.com; dkim=pass; spf=pass; dmarc=pass'],
        },
        textBody: 'Here is your weekly curated newsletter on Flutter development and distributed systems.',
      );

      final norm = Normalizer.normalize(msg);
      final verdict = await Classifier.score(norm, store);

      expect(verdict.label, equals(Label.newsletter));
      expect(verdict.spamScore, lessThan(0.60));

      final ids = verdict.evidence.map((e) => e.id).toSet();
      expect(ids.contains('stage_b_list_unsubscribe'), isTrue);
      expect(ids.contains('stage_b_newsletter'), isTrue);
    });

    test('community blocklist match elevates spam verdict', () async {
      final msg = Message(
        headers: {'from': ['unknown@legit-looking.org']},
        textBody: 'Please review the attached project schedule.',
      );

      final norm = Normalizer.normalize(msg);
      final signals = const Signals(communityBlocklistMatch: true);
      final verdict = await Classifier.score(norm, store, signals);

      expect(verdict.label, equals(Label.spam));
      expect(verdict.evidence.any((e) => e.id == 'community_blocklist'), isTrue);
    });

    test('block rule forces 1.0 spamScore and sender_blocked evidence', () async {
      final msg = Message(
        headers: {'from': ['friend@example.com'], 'subject': ['Hello']},
        textBody: 'Normal friendly email content.',
      );
      final norm = Normalizer.normalize(msg);
      final signals = const Signals(senderRule: SenderRuleAction.block);
      final verdict = await Classifier.score(norm, store, signals);

      expect(verdict.spamScore, equals(1.0));
      expect(verdict.label, equals(Label.spam));
      expect(verdict.evidence.any((e) => e.id == 'sender_blocked'), isTrue);
    });

    test('allow rule caps spamScore at 0.05 and keeps sender_allowed evidence', () async {
      final msg = Message(
        headers: {
          'from': ['spammer@bad.com'],
          'subject': ['Claim your lottery winnings now'],
        },
        textBody: 'Congratulations! You won the international lottery reward! Claim your payout immediately.',
      );
      final norm = Normalizer.normalize(msg);
      final signals = const Signals(senderRule: SenderRuleAction.allow);
      final verdict = await Classifier.score(norm, store, signals);

      expect(verdict.spamScore, lessThanOrEqualTo(0.05));
      expect(verdict.label, isNot(equals(Label.spam)));
      expect(verdict.evidence.any((e) => e.id == 'sender_allowed'), isTrue);
    });

    test('known contact with spammy Bayes is capped at < 0.90', () async {
      final msg = Message(
        headers: {
          'from': ['friend@example.com'],
          'subject': ['Claim your lottery winnings now'],
        },
        textBody: 'Congratulations! You won the international lottery reward! Claim your payout immediately.',
      );
      final norm = Normalizer.normalize(msg);

      // Without knownContact, spam score is high (>= 0.60)
      final plainVerdict = await Classifier.score(norm, store);
      expect(plainVerdict.spamScore, greaterThanOrEqualTo(0.60));

      // With knownContact, capped at 0.89 so it is never auto-moved to Junk
      final contactSignals = const Signals(knownContact: true);
      final contactVerdict = await Classifier.score(norm, store, contactSignals);

      expect(contactVerdict.spamScore, lessThan(0.90));
      expect(contactVerdict.evidence.any((e) => e.id == 'known_contact'), isTrue);
    });

    test('known contact with link_mismatch phishing is not capped', () async {
      final msg = Message(
        headers: {
          'from': ['friend@example.com'],
          'subject': ['Important notice regarding your lottery'],
        },
        textBody: 'Urgent lottery security update https://paypal.com',
        htmlBody: '<a href="https://evil-phish.com/steal">https://paypal.com/verify</a>',
      );
      final norm = Normalizer.normalize(msg);
      final signals = const Signals(knownContact: true);
      final verdict = await Classifier.score(norm, store, signals);

      expect(verdict.evidence.any((e) => e.id == 'link_mismatch'), isTrue);
      expect(verdict.isPhishing, isTrue);
      // Link mismatch adds +2.5 logit, bayes adds spam, so uncapped it reaches >= 0.90
      expect(verdict.spamScore, greaterThanOrEqualTo(0.90));
    });
  });
}
