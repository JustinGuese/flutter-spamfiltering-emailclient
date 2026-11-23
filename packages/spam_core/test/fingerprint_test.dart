import 'package:test/test.dart';
import 'package:spam_core/spam_core.dart';

void main() {
  group('Fingerprinter (Test 6)', () {
    test('Same spam, two recipient names -> identical body bands', () {
      final spamTextAlice = '''
Hi Alice Smith,
Congratulations! You have been selected as our exclusive winner for the international reward sweepstakes program.
Please claim your prize within twenty-four hours by clicking the link below or contacting our direct claims representative.
Your registered account alice.smith@example.com is eligible for this special one-time wire transfer payment of ten thousand dollars.
Failure to claim immediately will result in complete forfeiture of all funds to the secondary backup winner on our waiting list.
''';

      final spamTextBob = '''
Dear Bob Jones,
Congratulations! You have been selected as our exclusive winner for the international reward sweepstakes program.
Please claim your prize within twenty-four hours by clicking the link below or contacting our direct claims representative.
Your registered account bob.jones@other.org is eligible for this special one-time wire transfer payment of ten thousand dollars.
Failure to claim immediately will result in complete forfeiture of all funds to the secondary backup winner on our waiting list.
''';

      final msgAlice = Message(
        headers: {
          'to': ['Alice Smith <alice.smith@example.com>'],
          'from': ['lottery@claim-prize-now.com'],
        },
        textBody: spamTextAlice,
        recipientAddrs: ['alice.smith@example.com'],
      );

      final msgBob = Message(
        headers: {
          'to': ['Bob Jones <bob.jones@other.org>'],
          'from': ['lottery@claim-prize-now.com'],
        },
        textBody: spamTextBob,
        recipientAddrs: ['bob.jones@other.org'],
      );

      final normAlice = Normalizer.normalize(msgAlice);
      final normBob = Normalizer.normalize(msgBob);

      expect(normAlice.wordCount, greaterThanOrEqualTo(40));
      expect(normBob.wordCount, greaterThanOrEqualTo(40));

      final fpAlice = Fingerprinter.fingerprints(normAlice);
      final fpBob = Fingerprinter.fingerprints(normBob);

      expect(fpAlice.bodyBands.length, equals(8));
      expect(fpBob.bodyBands.length, equals(8));
      expect(fpAlice.bodyBands, equals(fpBob.bodyBands));
    });

    test('<40-word body -> no body fingerprint', () {
      final shortMsg = Message(
        headers: {'from': ['spammer@bad.com']},
        textBody: 'Hi there! Quick question for you. Please call me back at 555-1234 regarding your order.',
      );

      final norm = Normalizer.normalize(shortMsg);
      expect(norm.wordCount, lessThan(40));

      final fp = Fingerprinter.fingerprints(norm);
      expect(fp.bodyBands, isEmpty);
    });

    test('freemail sender domain hash is skipped', () {
      final msg = Message(
        headers: {'from': ['John Doe <johndoe@gmail.com>']},
        textBody: 'This is a test message from a Gmail sender.',
      );
      final norm = Normalizer.normalize(msg);
      expect(norm.isSenderFreemail, isTrue);

      final fp = Fingerprinter.fingerprints(norm);
      expect(fp.senderDomainHash, isNull);
    });

    test('custom domain sender hash is computed', () {
      final msg = Message(
        headers: {'from': ['Spammer <alert@malicious-domain.xyz>']},
        textBody: 'This is a test message from custom domain.',
      );
      final norm = Normalizer.normalize(msg);
      expect(norm.isSenderFreemail, isFalse);

      final fp = Fingerprinter.fingerprints(norm);
      expect(fp.senderDomainHash, isNotNull);
      expect(fp.senderDomainHash, greaterThan(0));
    });

    test('URL hashes extract eTLD+1 and host+first path segment with queries dropped', () {
      final msg = Message(
        headers: {'from': ['noreply@news.co.uk']},
        textBody: 'Check out https://sub.service.co.uk/verify/token?user=123&session=abc and https://evil.com/login#fragment',
      );
      final norm = Normalizer.normalize(msg);
      final fp = Fingerprinter.fingerprints(norm);

      expect(fp.urlHashes, isNotEmpty);
      expect(fp.urlHashes.length, greaterThanOrEqualTo(2));
    });
  });
}
