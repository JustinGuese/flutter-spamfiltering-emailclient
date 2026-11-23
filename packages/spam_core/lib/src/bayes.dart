import 'dart:async';
import 'dart:math' as math;
import 'contracts.dart';

/// Result of Robinson-Fisher Stage-A Bayes classification.
class BayesResult {
  final double score;
  final double hStat;
  final double sStat;
  final double hProbability;
  final double sProbability;
  final int tokenCount;
  final bool isUnsure;

  const BayesResult({
    required this.score,
    required this.hStat,
    required this.sStat,
    required this.hProbability,
    required this.sProbability,
    required this.tokenCount,
    required this.isUnsure,
  });
}

/// Robinson-Fisher chi-squared Bayes classifier.
class BayesClassifier {
  static const double priorSpamProbability = 0.5;
  static const double priorWeight = 1.0;
  static const double epsilon = 0.0001;
  static const double unsureLower = 0.40;
  static const double unsureUpper = 0.60;

  /// Computes the upper tail / survival function Q(df, x) = P(chi2_df >= x)
  /// for even degrees of freedom df = 2k.
  static double chi2UpperTail(int df, double x) {
    if (x <= 0.0) return 1.0;
    final k = df ~/ 2;
    if (k <= 0) return 1.0;

    final w = x / 2.0;
    if (w > 700.0) return 0.0; // Avoid underflow

    var sum = 0.0;
    var term = 1.0;

    for (var j = 0; j < k; j++) {
      if (j > 0) {
        term *= w / j;
      }
      sum += term;
    }

    final result = math.exp(-w) * sum;
    return result.clamp(0.0, 1.0);
  }

  /// Combines token spam probabilities using Robinson-Fisher chi-squared.
  static double robinsonScore(List<double> probabilities) {
    if (probabilities.isEmpty) return priorSpamProbability;

    final k = probabilities.length;
    var hStat = 0.0;
    var sStat = 0.0;

    for (final p in probabilities) {
      final clampedP = p.clamp(epsilon, 1.0 - epsilon);
      hStat += -2.0 * math.log(1.0 - clampedP);
      sStat += -2.0 * math.log(clampedP);
    }

    final hProb = chi2UpperTail(2 * k, hStat);
    final sProb = chi2UpperTail(2 * k, sStat);

    final r = (1.0 + sProb - hProb) / 2.0;
    return r.clamp(0.0, 1.0);
  }

  /// Evaluates Robinson-Fisher Bayes score for a list of token hashes.
  static Future<BayesResult> scoreTokens(
    List<int> tokenHashes,
    TokenStore store, {
    int totalSpamMessages = 0,
    int totalHamMessages = 0,
    double unsureLow = unsureLower,
    double unsureHigh = unsureUpper,
  }) async {
    final probs = <double>[];

    for (final hash in tokenHashes) {
      final counts = await store.counts(hash);
      final s = counts.spam;
      final h = counts.ham;

      // Gary Robinson smoothed probability
      final double tokenProb;
      if (s == 0 && h == 0) {
        tokenProb = priorSpamProbability;
      } else {
        final double fs = totalSpamMessages > 0 ? (s / totalSpamMessages) : (s / (s + h));
        final double fh = totalHamMessages > 0 ? (h / totalHamMessages) : (h / (s + h));
        final raw = (fs + fh > 0.0) ? (fs / (fs + fh)) : priorSpamProbability;
        final n = s + h;
        tokenProb = (priorWeight * priorSpamProbability + n * raw) / (priorWeight + n);
      }

      // Include tokens that deviate from neutral
      if ((tokenProb - priorSpamProbability).abs() >= 0.01) {
        probs.add(tokenProb);
      }
    }

    if (probs.isEmpty) {
      return const BayesResult(
        score: priorSpamProbability,
        hStat: 0.0,
        sStat: 0.0,
        hProbability: 0.5,
        sProbability: 0.5,
        tokenCount: 0,
        isUnsure: true,
      );
    }

    final k = probs.length;
    var hStat = 0.0;
    var sStat = 0.0;

    for (final p in probs) {
      final clampedP = p.clamp(epsilon, 1.0 - epsilon);
      hStat += -2.0 * math.log(1.0 - clampedP);
      sStat += -2.0 * math.log(clampedP);
    }

    final hProb = chi2UpperTail(2 * k, hStat);
    final sProb = chi2UpperTail(2 * k, sStat);
    final r = ((1.0 + sProb - hProb) / 2.0).clamp(0.0, 1.0);

    final unsure = (r >= unsureLow && r <= unsureHigh);

    return BayesResult(
      score: r,
      hStat: hStat,
      sStat: sStat,
      hProbability: hProb,
      sProbability: sProb,
      tokenCount: k,
      isUnsure: unsure,
    );
  }
}
