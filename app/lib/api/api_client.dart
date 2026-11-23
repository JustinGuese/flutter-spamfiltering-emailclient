import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:df_firebase_auth/df_firebase_auth.dart';

/// Authenticated API client provider configured to inject Firebase ID token (JWT)
/// rather than raw uid into Authorization Bearer headers.
final authenticatedDioProvider = Provider<Dio>((ref) {
  final dio = Dio(
    BaseOptions(
      baseUrl: const String.fromEnvironment('BACKEND_URL', defaultValue: 'http://localhost:8000'),
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      headers: {'Accept': 'application/json'},
    ),
  );

  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) async {
        final user = ref.read(currentUserProvider);
        if (user != null) {
          final token = await user.getIdToken();
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
        }
        handler.next(options);
      },
    ),
  );

  return dio;
});

/// Override for df_firebase_auth's apiClientProvider
final apiClientOverride = apiClientProvider.overrideWith((ref) => ref.watch(authenticatedDioProvider));
