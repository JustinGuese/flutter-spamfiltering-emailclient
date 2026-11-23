import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../app/log.dart';

/// Downloads the advanced neural ONNX model when entitled.
class ModelDownloader {
  final Dio dio;

  ModelDownloader({required this.dio});

  /// Fetches model download URL from backend and saves the ONNX weights locally.
  Future<File?> downloadModelIfEntitled() async {
    try {
      final res = await dio.get('/v1/models/advanced');
      if (res.statusCode != 200) return null;

      final data = res.data as Map<String, dynamic>;
      final downloadUrl = data['download_url'] as String;

      final dir = await getApplicationDocumentsDirectory();
      final modelFile = File(p.join(dir.path, 'advanced_spam_model.onnx'));

      await dio.download(downloadUrl, modelFile.path);
      return modelFile;
    } catch (e, st) {
      logError('model download', e, st);
      return null;
    }
  }

  Future<bool> hasLocalModel() async {
    final dir = await getApplicationDocumentsDirectory();
    final modelFile = File(p.join(dir.path, 'advanced_spam_model.onnx'));
    return modelFile.existsSync();
  }
}
