import 'dart:convert';
import 'dart:io';
import 'package:spam_core/spam_core.dart';

/// Performance metrics for spam classification.
class EvalMetrics {
  final int total;
  final int totalSpam;
  final int totalHam;
  final int truePositives; // Spam scored >= 0.6
  final int spamAutoMoved; // Spam scored >= 0.9
  final int falseNegatives; // Spam scored < 0.6
  final int trueNegatives; // Ham scored < 0.6
  final int hamFlagged; // Ham scored >= 0.6 (false positives)
  final int hamAutoMoved; // Ham scored >= 0.9 (severe false positives)
  final int newsletterCorrect;
  final int newsletterTotal;

  const EvalMetrics({
    required this.total,
    required this.totalSpam,
    required this.totalHam,
    required this.truePositives,
    required this.spamAutoMoved,
    required this.falseNegatives,
    required this.trueNegatives,
    required this.hamFlagged,
    required this.hamAutoMoved,
    required this.newsletterCorrect,
    required this.newsletterTotal,
  });

  /// Share of spam scored >= 0.60
  double get spamRecall =>
      totalSpam > 0 ? truePositives / totalSpam : 0.0;

  /// Share of ham scored >= 0.60 (flagged for review)
  double get hamFlagRate =>
      totalHam > 0 ? hamFlagged / totalHam : 0.0;

  /// Share of ham scored >= 0.90 (auto-moved to Junk; must be 0)
  double get hamAutoMoveRate =>
      totalHam > 0 ? hamAutoMoved / totalHam : 0.0;

  /// Alias for hamFlagRate
  double get falsePositiveRate => hamFlagRate;

  /// Precision: TP / (TP + FP)
  double get precision =>
      (truePositives + hamFlagged > 0)
          ? truePositives / (truePositives + hamFlagged)
          : 0.0;

  double get spamPrecision => precision;

  /// Harmonic mean of precision and recall
  double get f1 =>
      (precision + spamRecall > 0)
          ? (2.0 * precision * spamRecall) / (precision + spamRecall)
          : 0.0;

  double get newsletterAccuracy =>
      (newsletterTotal > 0) ? newsletterCorrect / newsletterTotal : 0.0;

  Map<String, dynamic> toJson() => {
    'total': total,
    'total_spam': totalSpam,
    'total_ham': totalHam,
    'true_positives': truePositives,
    'spam_auto_moved': spamAutoMoved,
    'false_negatives': falseNegatives,
    'true_negatives': trueNegatives,
    'false_positives': hamFlagged,
    'ham_flagged': hamFlagged,
    'ham_auto_moved': hamAutoMoved,
    'spam_recall': spamRecall,
    'ham_flag_rate': hamFlagRate,
    'ham_auto_move_rate': hamAutoMoveRate,
    'precision': precision,
    'f1': f1,
    'newsletter_accuracy': newsletterAccuracy,
    'newsletter_total': newsletterTotal,
    'newsletter_correct': newsletterCorrect,
  };

  void printSummary() {
    print('----------------------------------------');
    print('Spam Filter Evaluation Results:');
    print('Total samples evaluated:     $total (Spam: $totalSpam, Ham: $totalHam)');
    print('Spam Recall (TPR >= 0.6):    ${(spamRecall * 100).toStringAsFixed(2)}% ($truePositives / $totalSpam)');
    print('Spam Auto-Moved (>= 0.9):    ${((totalSpam > 0 ? spamAutoMoved / totalSpam : 0) * 100).toStringAsFixed(2)}% ($spamAutoMoved / $totalSpam)');
    print('Ham Flag Rate (FPR >= 0.6):  ${(hamFlagRate * 100).toStringAsFixed(3)}% ($hamFlagged / $totalHam) [Target <= 5%]');
    print('Ham Auto-Move Rate (>= 0.9): ${(hamAutoMoveRate * 100).toStringAsFixed(3)}% ($hamAutoMoved / $totalHam) [Target: 0%]');
    print('Precision:                   ${(precision * 100).toStringAsFixed(2)}%');
    print('F1 Score:                    ${(f1 * 100).toStringAsFixed(2)}%');
    if (newsletterTotal > 0) {
      print('Newsletter Accuracy:         ${(newsletterAccuracy * 100).toStringAsFixed(2)}% ($newsletterCorrect / $newsletterTotal)');
    }
    print('Confusion Counts:            TP=$truePositives, FP=$hamFlagged, TN=$trueNegatives, FN=$falseNegatives');
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
    var spamAuto = 0;
    var fn = 0;
    var tn = 0;
    var hamFlag = 0;
    var hamAuto = 0;
    var totalSpam = 0;
    var totalHam = 0;
    var newsCorrect = 0;
    var newsTotal = 0;

    for (final sample in labeledSamples) {
      final msg = sample.key;
      final expected = sample.value;
      final normalized = Normalizer.normalize(msg);
      final verdict = await Classifier.score(normalized, store);

      if (expected == Label.spam) {
        totalSpam++;
        if (verdict.spamScore >= 0.60) {
          tp++;
          if (verdict.spamScore >= 0.90) {
            spamAuto++;
          }
        } else {
          fn++;
        }
      } else {
        totalHam++;
        if (verdict.spamScore >= 0.60) {
          hamFlag++;
          if (verdict.spamScore >= 0.90) {
            hamAuto++;
          }
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
      totalSpam: totalSpam,
      totalHam: totalHam,
      truePositives: tp,
      spamAutoMoved: spamAuto,
      falseNegatives: fn,
      trueNegatives: tn,
      hamFlagged: hamFlag,
      hamAutoMoved: hamAuto,
      newsletterCorrect: newsCorrect,
      newsletterTotal: newsTotal,
    );
  }

  /// Loads token store from model JSON file.
  static Future<MemoryTokenStore> loadModel(File file) async {
    final content = await file.readAsString();
    final json = jsonDecode(content) as Map<String, dynamic>;
    final totalSpam = (json['total_spam'] as num?)?.toInt() ??
        (json['totals']?['spam'] as num?)?.toInt() ??
        0;
    final totalHam = (json['total_ham'] as num?)?.toInt() ??
        (json['totals']?['ham'] as num?)?.toInt() ??
        0;
    final tokensJson = json['tokens'] as Map<String, dynamic>? ?? {};

    final initial = <int, TokenCounts>{};
    for (final entry in tokensJson.entries) {
      final hash = int.tryParse(entry.key) ?? Tokenizer.hashToken(entry.key);
      final map = entry.value as Map<String, dynamic>;
      initial[hash] = TokenCounts(
        spam: map['spam'] as int? ?? 0,
        ham: map['ham'] as int? ?? 0,
        newsletter: map['newsletter'] as int? ?? 0,
        inbox: map['inbox'] as int? ?? 0,
      );
    }
    return MemoryTokenStore(initial, totalSpam, totalHam);
  }
}
