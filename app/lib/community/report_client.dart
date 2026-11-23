import 'package:dio/dio.dart';
import 'package:spam_core/spam_core.dart';
import 'pow.dart';
import 'app_check.dart';
import '../api/backend_config.dart';
import '../app/log.dart';

/// Plain Dio client communicating anonymously with the community API.
/// Never carries uid, ID token, device id, install id, or user-identifying headers.
class CommunityReportClient {
  final Dio dio;
  final String baseUrl;

  CommunityReportClient({
    Dio? dio,
    this.baseUrl = backendUrl,
  }) : dio = dio ?? Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
          headers: {'Accept': 'application/json'},
        ));

  /// Reports anonymous spam fingerprints.
  Future<bool> reportSpam(Fingerprints fingerprints) async {
    try {
      final appCheck = await AppCheckHelper.getToken();
      final pow = ProofOfWork.solve('report_${DateTime.now().millisecondsSinceEpoch}');

      final payload = <String, dynamic>{
        'body_bands': fingerprints.bodyBands,
        'url_hashes': fingerprints.urlHashes,
        if (fingerprints.senderDomainHash != null)
          'sender_domain_hash': fingerprints.senderDomainHash,
        'pow': pow,
        'app_check': ?appCheck,
      };

      final response = await dio.post(
        '$baseUrl/v1/reports',
        data: payload,
      );
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e, st) {
      logError('community report', e, st);
      return false;
    }
  }

  /// Votes ham for fingerprints that were falsely identified as spam.
  Future<bool> voteHam(List<int> hashes) async {
    try {
      final response = await dio.post(
        '$baseUrl/v1/votes/ham',
        data: {'hashes': hashes},
      );
      return response.statusCode == 200 || response.statusCode == 204;
    } catch (e, st) {
      logError('community vote ham', e, st);
      return false;
    }
  }

  /// Fetches complete blocklist snapshot.
  Future<Map<String, dynamic>?> fetchSnapshot() async {
    try {
      final res = await dio.get('$baseUrl/v1/blocklist/snapshot');
      if (res.statusCode == 200) {
        return res.data as Map<String, dynamic>;
      }
    } catch (e, st) {
      logError('community snapshot', e, st);
    }
    return null;
  }

  /// Fetches blocklist delta since [sinceVersion].
  Future<Map<String, dynamic>?> fetchDelta(int sinceVersion) async {
    try {
      final res = await dio.get(
        '$baseUrl/v1/blocklist/delta',
        queryParameters: {'since': sinceVersion},
      );
      if (res.statusCode == 200) {
        return res.data as Map<String, dynamic>;
      }
    } catch (e, st) {
      logError('community delta', e, st);
    }
    return null;
  }
}
