import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spamfiltering_emailclient/mail/oauth/oauth_config.dart';
import 'package:spamfiltering_emailclient/mail/oauth/oauth_service.dart';
import 'package:spamfiltering_emailclient/mail/oauth/oauth_types.dart';
import 'package:df_oauth/df_oauth.dart';

void main() {
  group('OAuthConfig', () {
    test('Google config includes mail scopes and offline params', () {
      final config = OAuthConfig.forProvider(
        OAuthProvider.google,
        customClientId: 'google-client-id-123',
        customRedirectUri: 'http://127.0.0.1:8080',
      );

      expect(config.clientId, 'google-client-id-123');
      expect(config.authorizationEndpoint,
          'https://accounts.google.com/o/oauth2/v2/auth');
      expect(config.tokenEndpoint, 'https://oauth2.googleapis.com/token');
      expect(config.scopes, contains('https://mail.google.com/'));
      expect(config.scopes, contains('openid'));
      expect(config.scopes, contains('email'));
      expect(config.scopes, contains('profile'));
      expect(config.additionalParameters?['access_type'], 'offline');
    });

    test('Microsoft config includes mail scopes and common tenant', () {
      final config = OAuthConfig.forProvider(
        OAuthProvider.microsoft,
        customClientId: 'ms-client-id-456',
        customRedirectUri: 'http://127.0.0.1:8080',
      );

      expect(config.clientId, 'ms-client-id-456');
      expect(config.authorizationEndpoint,
          'https://login.microsoftonline.com/common/oauth2/v2.0/authorize');
      expect(config.tokenEndpoint,
          'https://login.microsoftonline.com/common/oauth2/v2.0/token');
      expect(config.scopes,
          contains('https://outlook.office.com/IMAP.AccessAsUser.All'));
      expect(config.scopes,
          contains('https://outlook.office.com/SMTP.Send'));
      expect(config.scopes, contains('offline_access'));
    });
  });

  group('OAuthService', () {
    test('PKCE S256 matches RFC 7636 Appendix B test vector', () {
      // RFC 7636 Appendix B test vector:
      // code_verifier: dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk
      // code_challenge: E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM
      const verifier = 'dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk';
      const expectedChallenge = 'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM';

      final challenge = DfOAuthPkce.generateCodeChallenge(verifier);
      expect(challenge, expectedChallenge);

      // Verify OAuthService.generatePkce produces valid length and challenge
      final generated = OAuthService.generatePkce();
      expect(generated.verifier.length, greaterThanOrEqualTo(43));
      expect(generated.verifier.length, lessThanOrEqualTo(128));
      expect(DfOAuthPkce.generateCodeChallenge(generated.verifier),
          generated.challenge);
    });

    test('exchangeCode sends code_verifier and returns OAuthTokens', () async {
      final dio = Dio();
      dio.httpClientAdapter = _MockHttpClientAdapter((options) async {
        if (options.uri.path.contains('/token')) {
          final data = options.data as Map<String, dynamic>;
          expect(data['grant_type'], 'authorization_code');
          expect(data['code'], 'test_auth_code');
          expect(data['code_verifier'], 'test_verifier');

          return ResponseBody.fromString(
            jsonEncode({
              'access_token': 'new_access_token',
              'refresh_token': 'new_refresh_token',
              'expires_in': 3600,
              'id_token': 'test_id_token',
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

      final service = OAuthService(dio: dio);
      final testConfig = DfOAuthProviderConfig(
        authorizationEndpoint: 'https://example.com/auth',
        tokenEndpoint: 'https://example.com/token',
        scopes: ['openid'],
        clientId: 'test-client',
        redirectUri: 'http://127.0.0.1:8080',
      );

      final tokens = await service.exchangeCode(
        provider: OAuthProvider.google,
        code: 'test_auth_code',
        codeVerifier: 'test_verifier',
        configOverride: testConfig,
      );

      expect(tokens.accessToken, 'new_access_token');
      expect(tokens.refreshToken, 'new_refresh_token');
      expect(tokens.idToken, 'test_id_token');
      expect(tokens.expiresAt.isAfter(DateTime.now()), isTrue);
    });

    test('refresh retains existing refresh token when omitted in server response',
        () async {
      final dio = Dio();
      dio.httpClientAdapter = _MockHttpClientAdapter((options) async {
        if (options.uri.path.contains('/token')) {
          final data = options.data as Map<String, dynamic>;
          expect(data['grant_type'], 'refresh_token');
          expect(data['refresh_token'], 'existing_refresh_token');

          // Response intentionally omits refresh_token
          return ResponseBody.fromString(
            jsonEncode({
              'access_token': 'refreshed_access_token',
              'expires_in': 3600,
            }),
            200,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
            },
          );
        }
        return ResponseBody.fromString('Not Found', 404);
      });

      final service = OAuthService(dio: dio);
      final testConfig = DfOAuthProviderConfig(
        authorizationEndpoint: 'https://example.com/auth',
        tokenEndpoint: 'https://example.com/token',
        scopes: ['openid'],
        clientId: 'test-client',
        redirectUri: 'http://127.0.0.1:8080',
      );

      final tokens = await service.refresh(
        provider: OAuthProvider.google,
        refreshToken: 'existing_refresh_token',
        configOverride: testConfig,
      );

      expect(tokens.accessToken, 'refreshed_access_token');
      // Preserved!
      expect(tokens.refreshToken, 'existing_refresh_token');
      expect(tokens.expiresAt.isAfter(DateTime.now()), isTrue);
    });

    test('refresh maps invalid_grant to ReauthRequiredException', () async {
      final dio = Dio();
      dio.httpClientAdapter = _MockHttpClientAdapter((options) async {
        return ResponseBody.fromString(
          jsonEncode({
            'error': 'invalid_grant',
            'error_description': 'Token has been expired or revoked.',
          }),
          400,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      });

      final service = OAuthService(dio: dio);
      final testConfig = DfOAuthProviderConfig(
        authorizationEndpoint: 'https://example.com/auth',
        tokenEndpoint: 'https://example.com/token',
        scopes: ['openid'],
        clientId: 'test-client',
        redirectUri: 'http://127.0.0.1:8080',
      );

      expect(
        () => service.refresh(
          provider: OAuthProvider.microsoft,
          refreshToken: 'revoked_token',
          accountId: 'acc_ms_1',
          email: 'user@outlook.com',
          configOverride: testConfig,
        ),
        throwsA(
          isA<ReauthRequiredException>()
              .having((e) => e.accountId, 'accountId', 'acc_ms_1')
              .having((e) => e.email, 'email', 'user@outlook.com')
              .having((e) => e.provider, 'provider', OAuthProvider.microsoft),
        ),
      );
    });

    test('identityFrom extracts email and displayName from JWT ID token', () {
      final service = OAuthService();

      // Create a valid JWT with header and payload
      final header = base64Url.encode(utf8.encode(jsonEncode({'alg': 'RS256', 'typ': 'JWT'}))).replaceAll('=', '');
      final payload = base64Url.encode(utf8.encode(jsonEncode({
        'sub': 'user-sub-12345',
        'email': 'alice@datafortress.cloud',
        'name': 'Alice Wonder',
      }))).replaceAll('=', '');
      final idToken = '$header.$payload.fake_signature';

      final identity = service.identityFrom(idToken);
      expect(identity.email, 'alice@datafortress.cloud');
      expect(identity.displayName, 'Alice Wonder');
    });

    test('identityFrom falls back to upn or preferred_username if email claim is absent', () {
      final service = OAuthService();

      final header = base64Url.encode(utf8.encode(jsonEncode({'alg': 'RS256'}))).replaceAll('=', '');
      final payload = base64Url.encode(utf8.encode(jsonEncode({
        'sub': 'ms-sub-6789',
        'preferred_username': 'bob@company.com',
        'given_name': 'Bob',
        'family_name': 'Builder',
      }))).replaceAll('=', '');
      final idToken = '$header.$payload.fake_signature';

      final identity = service.identityFrom(idToken);
      expect(identity.email, 'bob@company.com');
      expect(identity.displayName, 'Bob Builder');
    });

    test('identityFrom throws FormatException if no email or username is present', () {
      final service = OAuthService();

      final header = base64Url.encode(utf8.encode(jsonEncode({'alg': 'RS256'}))).replaceAll('=', '');
      final payload = base64Url.encode(utf8.encode(jsonEncode({
        'sub': 'nameless-sub',
      }))).replaceAll('=', '');
      final idToken = '$header.$payload.fake_signature';

      expect(() => service.identityFrom(idToken), throwsFormatException);
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
