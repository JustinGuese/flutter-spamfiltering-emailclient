import 'package:test/test.dart';
import 'package:spam_core/spam_core.dart';

void main() {
  group('Tokenizer (S4 Multilingual & Obfuscation)', () {
    test('ASCII sentence tokens are identical to pre-change output', () {
      final msg = const Message(
        headers: {
          'subject': ['Quarterly Report'],
          'from': ['cfo@investor.com'],
        },
        textBody: 'The quarterly financial results are now available.',
      );

      final norm = Normalizer.normalize(msg);
      final tokens = Tokenizer.tokens(norm);

      // Hard-coded expected tokens matching pre-change tokenizer output
      final expected = <String>[
        // Body words
        'the', 'quarterly', 'financial', 'results', 'are', 'now', 'available.',
        // OSB bigrams
        'the+quarterly', 'the+_financial', 'the+__results', 'the+___are',
        'quarterly+financial', 'quarterly+_results', 'quarterly+__are', 'quarterly+___now',
        'financial+results', 'financial+_are', 'financial+__now', 'financial+___available.',
        'results+are', 'results+_now', 'results+__available.',
        'are+now', 'are+_available.',
        'now+available.',
        // Headers
        'subj:quarterly', 'subj:report', 'from-dom:investor.com', 'list-unsub:absent',
      ];

      expect(tokens.toSet(), equals(expected.toSet()));
    });

    test("Cyrillic 'Выигрыш приз' yields tokens", () {
      final msg = const Message(
        headers: {
          'subject': ['Срочно'],
          'from': ['lottery@promo.ru'],
        },
        textBody: 'Выигрыш приз ждет вас',
      );

      final norm = Normalizer.normalize(msg);
      final tokens = Tokenizer.tokens(norm);

      expect(tokens, contains('выигрыш'));
      expect(tokens, contains('приз'));
      expect(tokens, contains('ждет'));
      expect(tokens, contains('вас'));
      expect(tokens, contains('выигрыш+приз'));
      expect(tokens, contains('subj:срочно'));
    });

    test("'v1agra' yields 'deob:viagra'", () {
      final msg = const Message(
        headers: {'from': ['spammer@bad.com'], 'subject': ['Special disc0unt']},
        textBody: 'Buy cheap v1agra and fr3e \$ale at c.a.s.i.n.o today!',
      );

      final norm = Normalizer.normalize(msg);
      final tokens = Tokenizer.tokens(norm);

      expect(tokens, contains('v1agra'));
      expect(tokens, contains('deob:viagra'));
      expect(tokens, contains('deob:free'));
      expect(tokens, contains('deob:sale'));
      expect(tokens, contains('deob:casino'));
      expect(tokens, contains('deob:discount'));
    });

    test('Japanese text yields bigrams', () {
      final msg = const Message(
        headers: {'from': ['newsletter@tokyo.jp'], 'subject': ['お知らせ']},
        textBody: 'こんにちは世界',
      );

      final norm = Normalizer.normalize(msg);
      final tokens = Tokenizer.tokens(norm);

      // Character bigrams from "こんにちは世界"
      expect(tokens, contains('こん'));
      expect(tokens, contains('んに'));
      expect(tokens, contains('にち'));
      expect(tokens, contains('ちは'));
      expect(tokens, contains('は世'));
      expect(tokens, contains('世界'));

      // Character bigrams from subject "お知らせ"
      expect(tokens, contains('お知'));
      expect(tokens, contains('知ら'));
      expect(tokens, contains('らせ'));
    });
  });
}
