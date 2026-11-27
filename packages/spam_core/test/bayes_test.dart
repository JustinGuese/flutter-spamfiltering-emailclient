import 'dart:math' as math;
import 'package:test/test.dart';
import 'package:spam_core/spam_core.dart';

void main() {
  group('Bayes Robinson-Fisher (Test 7)', () {
    test('chi2UpperTail matches exact hand-computed values', () {
      // df=2, x=2.0 -> e^(-1.0) = 0.36787944117144233
      final q2 = BayesClassifier.chi2UpperTail(2, 2.0);
      expect(q2, closeTo(math.exp(-1.0), 1e-9));

      // df=4, x=4.0 -> e^(-2.0) * (1 + 2.0) = 3 * e^(-2) = 0.4060058497098381
      final q4 = BayesClassifier.chi2UpperTail(4, 4.0);
      expect(q4, closeTo(3.0 * math.exp(-2.0), 1e-9));

      // df=6, x=6.0 -> e^(-3) * (1 + 3 + 9/2) = 8.5 * e^(-3) = 0.42319008112684364
      final q6 = BayesClassifier.chi2UpperTail(6, 6.0);
      expect(q6, closeTo(8.5 * math.exp(-3.0), 1e-9));
    });

    test('robinsonScore matches hand-computed single-token probability', () {
      // k=1, p_1 = 0.8
      // H_stat = -2 * ln(0.2) = 3.2188758248682
      // S_stat = -2 * ln(0.8) = 0.4462871026284
      // H = exp(-1.6094379) = 0.2
      // S = exp(-0.2231435) = 0.8
      // R = (1 + 0.8 - 0.2) / 2 = 0.8
      final r = BayesClassifier.robinsonScore([0.8]);
      expect(r, closeTo(0.8, 1e-6));
    });

    test('robinsonScore with equal neutral probabilities yields 0.5', () {
      final r = BayesClassifier.robinsonScore([0.5, 0.5, 0.5]);
      expect(r, closeTo(0.5, 1e-6));
    });

    test('unsure band respected in scoreTokens', () async {
      final store = MemoryTokenStore();

      // Token 1: moderately spammy
      final hash1 = 1001;
      await store.apply(hash1, Label.spam, 6);
      await store.apply(hash1, Label.ham, 4);

      // Score for hash1 should be around 0.5..0.6, falling in the unsure band [0.40, 0.60]
      final resultUnsure = await BayesClassifier.scoreTokens([hash1], store);
      expect(resultUnsure.score, greaterThanOrEqualTo(0.40));
      expect(resultUnsure.score, lessThanOrEqualTo(0.65));
      expect(resultUnsure.isUnsure, isTrue);

      // Token 2: extremely spammy
      final hashSpam = 2002;
      await store.apply(hashSpam, Label.spam, 100);
      await store.apply(hashSpam, Label.ham, 0);

      final resultSpam = await BayesClassifier.scoreTokens([hashSpam], store);
      expect(resultSpam.score, greaterThan(0.90));
      expect(resultSpam.isUnsure, isFalse);

      // Token 3: extremely hammy
      final hashHam = 3003;
      await store.apply(hashHam, Label.spam, 0);
      await store.apply(hashHam, Label.ham, 100);

      final resultHam = await BayesClassifier.scoreTokens([hashHam], store);
      expect(resultHam.score, lessThan(0.10));
      expect(resultHam.isUnsure, isFalse);
    });

    test('class-size normalisation works with message totals', () async {
      final tokenHash = Tokenizer.hashToken('the');

      // 100 spam msgs trained on token "the" (s=100) and 100 ham msgs with "the" (h=100) -> neutral
      final store1 = MemoryTokenStore(null, 100, 100);
      await store1.apply(tokenHash, Label.spam, 100);
      await store1.apply(tokenHash, Label.ham, 100);

      final result1 = await BayesClassifier.scoreTokens(
        [tokenHash],
        store1,
        totalSpamMessages: 100,
        totalHamMessages: 100,
      );
      expect(result1.score, equals(0.5));
      expect(result1.tokenCount, equals(0)); // |0.5 - 0.5| < 0.1

      // With totals spam=10, ham=1000 and counts s=10, h=10 -> spam-leaning
      final store2 = MemoryTokenStore(null, 10, 1000);
      await store2.apply(tokenHash, Label.spam, 10);
      await store2.apply(tokenHash, Label.ham, 10);

      final result2 = await BayesClassifier.scoreTokens(
        [tokenHash],
        store2,
        totalSpamMessages: 10,
        totalHamMessages: 1000,
      );
      expect(result2.score, greaterThan(0.80));
      expect(result2.tokenCount, equals(1));
    });

    test('significant tokens limit to 150 most extreme and n cap', () async {
      final store = MemoryTokenStore();
      final hashes = <int>[];
      for (var i = 1; i <= 200; i++) {
        final h = 10000 + i;
        hashes.add(h);
        await store.apply(h, Label.spam, 10 + i);
        await store.apply(h, Label.ham, 0);
      }
      final result = await BayesClassifier.scoreTokens(hashes, store);
      expect(result.tokenCount, equals(150));
    });
  });
}
