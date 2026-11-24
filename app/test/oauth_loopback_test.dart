import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:df_oauth/df_oauth.dart';
import 'package:spamfiltering_emailclient/mail/oauth/oauth_flow.dart';

void main() {
  group('OAuthLoopback (Test 2)', () {
    const testConfig = DfOAuthProviderConfig(
      authorizationEndpoint: 'https://accounts.google.com/o/oauth2/v2/auth',
      tokenEndpoint: 'https://oauth2.googleapis.com/token',
      scopes: ['https://mail.google.com/', 'openid'],
      clientId: 'test-google-client-id.apps.googleusercontent.com',
      redirectUri: 'http://127.0.0.1',
    );

    DfOAuthClient createMockOAuthClient() {
      final dio = Dio();
      dio.httpClientAdapter = _MockHttpClientAdapter((options) async {
        if (options.uri.path.contains('/token')) {
          return ResponseBody.fromString(
            jsonEncode({
              'access_token': 'mock_access_token',
              'refresh_token': 'mock_refresh_token',
              'expires_in': 3600,
              'id_token': 'mock_id_token',
              'token_type': 'Bearer',
            }),
            200,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
            },
          );
        }
        return ResponseBody.fromString('Not Found', 404);
      });
      return DfOAuthClient(dio: dio);
    }

    test('server binds strictly to 127.0.0.1 (loopback IPv4)', () async {
      InternetAddress? boundAddress;
      int? requestedPort;
      int? boundPort;

      final flow = OAuthFlowLoopback(
        client: createMockOAuthClient(),
        serverBinder: (address, port) async {
          boundAddress = address as InternetAddress;
          requestedPort = port;
          final server = await HttpServer.bind(address, port);
          boundPort = server.port;
          return server;
        },
        launchUrlFn: (uri) async {
          final state = uri.queryParameters['state']!;
          final redirectUri = Uri.parse(uri.queryParameters['redirect_uri']!);
          final client = HttpClient();
          final req = await client.getUrl(redirectUri.replace(
            queryParameters: {'state': state, 'code': 'test_code'},
          ));
          final resp = await req.close();
          await resp.drain();
          client.close();
          return true;
        },
      );

      final tokens = await flow.authorize(
        OAuthProvider.google,
        configOverride: testConfig,
      );

      expect(boundAddress, equals(InternetAddress.loopbackIPv4));
      expect(boundAddress!.isLoopback, isTrue);
      expect(boundAddress!.address, equals('127.0.0.1'));
      expect(requestedPort, equals(0)); // Ephemeral port requested
      expect(boundPort, isNotNull);
      expect(boundPort, greaterThan(0));
      expect(tokens.accessToken, equals('mock_access_token'));
    });

    test('callback with wrong state is rejected and server closes', () async {
      int? serverPort;
      int? responseStatusCode;
      String? responseBody;

      final flow = OAuthFlowLoopback(
        client: createMockOAuthClient(),
        serverBinder: (address, port) async {
          final server = await HttpServer.bind(address, port);
          serverPort = server.port;
          return server;
        },
        launchUrlFn: (uri) async {
          final redirectUri = Uri.parse(uri.queryParameters['redirect_uri']!);
          final client = HttpClient();
          final req = await client.getUrl(redirectUri.replace(
            queryParameters: {
              'state': 'wrong_state_value',
              'code': 'valid_auth_code',
            },
          ));
          final resp = await req.close();
          responseStatusCode = resp.statusCode;
          responseBody = await resp.transform(utf8.decoder).join();
          client.close();
          return true;
        },
      );

      // authorize should throw DfOAuthStateException
      await expectLater(
        () => flow.authorize(OAuthProvider.google, configOverride: testConfig),
        throwsA(isA<DfOAuthStateException>()),
      );

      expect(responseStatusCode, equals(HttpStatus.badRequest));
      expect(responseBody, contains('state mismatch'));

      // Verify server closed immediately: subsequent connection must fail
      expect(serverPort, isNotNull);
      final client = HttpClient();
      expect(
        () async {
          final req = await client.getUrl(Uri.parse('http://127.0.0.1:$serverPort/'));
          final resp = await req.close();
          await resp.drain();
        },
        throwsA(isA<SocketException>()),
      );
      client.close();
    });

    test('callback with missing state is rejected and server closes', () async {
      int? serverPort;
      int? responseStatusCode;
      String? responseBody;

      final flow = OAuthFlowLoopback(
        client: createMockOAuthClient(),
        serverBinder: (address, port) async {
          final server = await HttpServer.bind(address, port);
          serverPort = server.port;
          return server;
        },
        launchUrlFn: (uri) async {
          final redirectUri = Uri.parse(uri.queryParameters['redirect_uri']!);
          final client = HttpClient();
          final req = await client.getUrl(redirectUri.replace(
            queryParameters: {
              'code': 'valid_auth_code',
            },
          ));
          final resp = await req.close();
          responseStatusCode = resp.statusCode;
          responseBody = await resp.transform(utf8.decoder).join();
          client.close();
          return true;
        },
      );

      await expectLater(
        () => flow.authorize(OAuthProvider.google, configOverride: testConfig),
        throwsA(isA<DfOAuthStateException>()),
      );

      expect(responseStatusCode, equals(HttpStatus.badRequest));
      expect(responseBody, contains('Missing OAuth state'));

      // Verify server closed
      expect(serverPort, isNotNull);
      final client = HttpClient();
      expect(
        () async {
          final req = await client.getUrl(Uri.parse('http://127.0.0.1:$serverPort/'));
          final resp = await req.close();
          await resp.drain();
        },
        throwsA(isA<SocketException>()),
      );
      client.close();
    });

    test('server closes after one single callback', () async {
      int? serverPort;
      String? expectedState;

      final flow = OAuthFlowLoopback(
        client: createMockOAuthClient(),
        serverBinder: (address, port) async {
          final server = await HttpServer.bind(address, port);
          serverPort = server.port;
          return server;
        },
        launchUrlFn: (uri) async {
          expectedState = uri.queryParameters['state'];
          final redirectUri = Uri.parse(uri.queryParameters['redirect_uri']!);
          final client = HttpClient();

          // First request: valid callback
          final req = await client.getUrl(redirectUri.replace(
            queryParameters: {
              'state': expectedState,
              'code': 'first_callback_code',
            },
          ));
          final resp = await req.close();
          expect(resp.statusCode, equals(HttpStatus.ok));
          await resp.drain();
          client.close();
          return true;
        },
      );

      final tokens = await flow.authorize(
        OAuthProvider.google,
        configOverride: testConfig,
      );

      expect(tokens.accessToken, equals('mock_access_token'));
      expect(tokens.refreshToken, equals('mock_refresh_token'));

      // A second request immediately following the first must fail because server is closed
      expect(serverPort, isNotNull);
      final secondClient = HttpClient();
      expect(
        () async {
          final req = await secondClient.getUrl(
            Uri.parse('http://127.0.0.1:$serverPort/?state=$expectedState&code=second_attempt'),
          );
          final resp = await req.close();
          await resp.drain();
        },
        throwsA(isA<SocketException>()),
      );
      secondClient.close();
    });

    test('server closes and completes with DfOAuthTimeoutException on timeout', () async {
      int? serverPort;

      final flow = OAuthFlowLoopback(
        client: createMockOAuthClient(),
        timeout: const Duration(milliseconds: 100),
        serverBinder: (address, port) async {
          final server = await HttpServer.bind(address, port);
          serverPort = server.port;
          return server;
        },
        launchUrlFn: (uri) async {
          // Do not send any callback to trigger timeout
          return true;
        },
      );

      await expectLater(
        () => flow.authorize(OAuthProvider.google, configOverride: testConfig),
        throwsA(isA<DfOAuthTimeoutException>()),
      );

      expect(serverPort, isNotNull);
      final client = HttpClient();
      expect(
        () async {
          final req = await client.getUrl(Uri.parse('http://127.0.0.1:$serverPort/'));
          final resp = await req.close();
          await resp.drain();
        },
        throwsA(isA<SocketException>()),
      );
      client.close();
    });

    test('throws OAuthNotConfiguredException when client ID is not configured', () async {
      final flow = OAuthFlowLoopback();

      // Without dart-define environment variables, isConfigured returns false
      expect(
        () => flow.authorize(OAuthProvider.google),
        throwsA(
          isA<OAuthNotConfiguredException>()
              .having((e) => e.provider, 'provider', OAuthProvider.google),
        ),
      );

      expect(
        () => flow.authorize(OAuthProvider.microsoft),
        throwsA(
          isA<OAuthNotConfiguredException>()
              .having((e) => e.provider, 'provider', OAuthProvider.microsoft),
        ),
      );
    });

    test('user cancellation in callback throws distinct OAuthCancelledException', () async {
      final flow = OAuthFlowLoopback(
        client: createMockOAuthClient(),
        launchUrlFn: (uri) async {
          final state = uri.queryParameters['state']!;
          final redirectUri = Uri.parse(uri.queryParameters['redirect_uri']!);
          final client = HttpClient();
          final req = await client.getUrl(redirectUri.replace(
            queryParameters: {
              'state': state,
              'error': 'access_denied',
              'error_description': 'User denied authorization request.',
            },
          ));
          final resp = await req.close();
          await resp.drain();
          client.close();
          return true;
        },
      );

      await expectLater(
        () => flow.authorize(OAuthProvider.google, configOverride: testConfig),
        throwsA(
          isA<OAuthCancelledException>()
              .having((e) => e.message, 'message', contains('User denied')),
        ),
      );
    });

    test('OAuthFlow.forPlatform dispatches according to target platform', () {
      final linuxFlow = OAuthFlow.forPlatform(platformOverride: TargetPlatform.linux);
      expect(linuxFlow, isA<OAuthFlowPlatform>());

      final windowsFlow = OAuthFlow.forPlatform(platformOverride: TargetPlatform.windows);
      expect(windowsFlow, isA<OAuthFlowPlatform>());

      final androidFlow = OAuthFlow.forPlatform(platformOverride: TargetPlatform.android);
      expect(androidFlow, isA<OAuthFlowPlatform>());

      final iosFlow = OAuthFlow.forPlatform(platformOverride: TargetPlatform.iOS);
      expect(iosFlow, isA<OAuthFlowPlatform>());

      final macosFlow = OAuthFlow.forPlatform(platformOverride: TargetPlatform.macOS);
      expect(macosFlow, isA<OAuthFlowPlatform>());
    });
  });
}

class _MockHttpClientAdapter implements HttpClientAdapter {
  final Future<ResponseBody> Function(RequestOptions options) _handler;

  _MockHttpClientAdapter(this._handler);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) {
    return _handler(options);
  }

  @override
  void close({bool force = false}) {}
}
