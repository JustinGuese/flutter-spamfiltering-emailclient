import 'dart:convert';
import 'dart:io';
import 'package:spam_core/spam_core.dart';

/// Performance metrics for spam classification.
class EvalMetrics {
  final int total;
  final int truePositives;
  final int falsePositives;
  final int trueNegatives;
  final int falseNegatives;
  final int newsletterCorrect;
  final int newsletterTotal;

  const EvalMetrics({
    required this.total,
    required this.truePositives,
    required this.falsePositives,
    required this.trueNegatives,
    required this.falseNegatives,
    required this.newsletterCorrect,
    required this.newsletterTotal,
  });

  double get spamRecall =>
      (truePositives + falseNegatives > 0) ? truePositives / (truePositives + falseNegatives) : 0.0;

  double get falsePositiveRate =>
      (falsePositives + trueNegatives > 0) ? falsePositives / (falsePositives + trueNegatives) : 0.0;

  double get spamPrecision =>
      (truePositives + falsePositives > 0) ? truePositives / (truePositives + falsePositives) : 0.0;

  double get newsletterAccuracy =>
      (newsletterTotal > 0) ? newsletterCorrect / newsletterTotal : 0.0;

  void printSummary() {
    print('----------------------------------------');
    print('Spam Filter Evaluation Results:');
    print('Total samples evaluated: $total');
    print('Spam Recall (TPR):       ${(spamRecall * 100).toStringAsFixed(2)}% ($truePositives / ${truePositives + falseNegatives})');
    print('False Positive Rate (FPR): ${(falsePositiveRate * 100).toStringAsFixed(3)}% ($falsePositives / ${falsePositives + trueNegatives}) [Target <= 0.1%]');
    print('Spam Precision:          ${(spamPrecision * 100).toStringAsFixed(2)}%');
    print('Newsletter Accuracy:     ${(newsletterAccuracy * 100).toStringAsFixed(2)}% ($newsletterCorrect / $newsletterTotal)');
    print('----------------------------------------');
  }
}

/// Evaluator that runs messages through Classifier against TokenStore.
class CorpusEvaluator {
  final TokenStore store;

  CorpusEvaluator(this.store);

  /// Evaluates labeled test samples.
  Future<EvalMetrics> evaluate(List<MapEntry<Message, Label>> labeledSamples) async {
    var tp = 0;
    var fp = 0;
    var tn = 0;
    var fn = 0;
    var newsCorrect = 0;
    var newsTotal = 0;

    for (final sample in labeledSamples) {
      final msg = sample.key;
      final expected = sample.value;
      final normalized = Normalizer.normalize(msg);
      final verdict = await Classifier.score(normalized, store);

      if (expected == Label.spam) {
        if (verdict.label == Label.spam) {
          tp++;
        } else {
          fn++;
        }
      } else {
        // Expected is Ham, Newsletter, or Inbox
        if (verdict.label == Label.spam) {
          fp++;
        } else {
          tn++;
        }

        if (expected == Label.newsletter) {
          newsTotal++;
          if (verdict.label == Label.newsletter) {
            newsCorrect++;
          }
        }
      }
    }

    return EvalMetrics(
      total: labeledSamples.length,
      truePositives: tp,
      falsePositives: fp,
      trueNegatives: tn,
      falseNegatives: fn,
      newsletterCorrect: newsCorrect,
      newsletterTotal: newsTotal,
    );
  }

  /// Loads token store from model JSON file.
  static Future<MemoryTokenStore> loadModel(File file) async {
    final content = await file.readAsString();
    final json = jsonDecode(content) as Map<String, dynamic>;
    final tokensJson = json['tokens'] as Map<String, dynamic>? ?? {};

    final initial = <int, TokenCounts>{};
    for (final entry in tokensJson.entries) {
      final hash = int.tryParse(entry.key);
      if (hash != null) {
        final map = entry.value as Map<String, dynamic>;
        initial[hash] = TokenCounts(
          spam: map['spam'] as int? ?? 0,
          ham: map['ham'] as int? ?? 0,
          newsletter: map['newsletter'] as int? ?? 0,
          inbox: map['inbox'] as int? ?? 0,
        );
      }
    }
    return MemoryTokenStore(initial);
  }
}
