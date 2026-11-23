import 'dart:io';
import 'package:spam_core/spam_core.dart';

/// On-device neural spam scorer (premium "Advanced AI model").
///
/// **Not implemented yet.** It needs two things that do not exist in this repo:
///   1. a trained, licence-clean ONNX classifier (see PLAN.md "Advanced AI model"), and
///   2. an ONNX runtime that works on all five platforms (`fonnx` or
///      `flutter_onnxruntime`, to be smoke-tested).
///
/// Until both land, [score] returns `null`, which the combiner treats as "no neural
/// signal". It must never return a made-up number: that would feed noise into the
/// spam decision for paying users.
class OnnxSpamScorer {
  final File? modelFile;

  OnnxSpamScorer({this.modelFile});

  /// Whether a real inference runtime is wired in. Flip to true only together with
  /// a real implementation of [score].
  static const bool runtimeAvailable = false;

  /// Returns a neural spam probability in [0, 1], or `null` when no model/runtime
  /// is available.
  Future<double?> score(Normalized normalized) async {
    if (!runtimeAvailable) return null;
    if (modelFile == null || !modelFile!.existsSync()) return null;
    return null;
  }
}
