import 'package:df_oauth/df_oauth.dart';
import 'package:dio/dio.dart';

import 'oauth_config.dart';
import 'oauth_types.dart';

/// Service responsible for OAuth token exchange, token refresh, and identity extraction.
///
/// Wraps [DfOAuthClient] from `df_oauth` and integrates with application-specific
/// types ([OAuthTokens], [OAuthIdentity], [ReauthRequiredException]).
/// Strictly avoids logging credentials or raw tokens.
class OAuthService {
  final DfOAuthClient _client;

  OAuthService({DfOAuthClient? client, Dio? dio})
      : _client = client ?? DfOAuthClient(dio: dio);

  /// Exchanges an authorization code and PKCE [codeVerifier] for [OAuthTokens].
  Future<OAuthTokens> exchangeCode({
    required OAuthProvider provider,
    required String code,
    required String codeVerifier,
    DfOAuthProviderConfig? configOverride,
    String? redirectUri,
  }) async {
    final config = configOverride ?? OAuthConfig.forProvider(provider);
    try {
      final dfTokens = await _client.exchangeCode(
        config: config,
        code: code,
        codeVerifier: codeVerifier,
        redirectUri: redirectUri,
      );
      return _mapTokens(dfTokens);
    } on DfOAuthInvalidGrantException {
      throw ReauthRequiredException(
        accountId: '',
        email: '',
        provider: provider,
      );
    }
  }

  /// Refreshes access token for [provider] using [refreshToken].
  ///
  /// Preserves the existing [refreshToken] if omitted by the server in the refresh response.
  /// Deduplicates concurrent refreshes for the same account/token via [flightKey].
  /// Throws [ReauthRequiredException] if server returns `invalid_grant`.
  Future<OAuthTokens> refresh({
    required OAuthProvider provider,
    required String refreshToken,
    String accountId = '',
    String email = '',
    DfOAuthProviderConfig? configOverride,
    String? flightKey,
  }) async {
    final config = configOverride ?? OAuthConfig.forProvider(provider);
    try {
      final dfTokens = await _client.refresh(
        config: config,
        refreshToken: refreshToken,
        flightKey: flightKey,
      );
      return _mapTokens(dfTokens);
    } on DfOAuthInvalidGrantException {
      throw ReauthRequiredException(
        accountId: accountId,
        email: email,
        provider: provider,
      );
    }
  }

  /// Extracts user identity ([email] and [displayName]) from an OpenID Connect [idToken] JWT payload.
  OAuthIdentity identityFrom(String idToken) {
    final claims = DfOAuthClaims.fromIdToken(idToken);
    final email = claims.email;
    if (email == null || email.isEmpty) {
      throw const FormatException('ID token does not contain a valid email claim.');
    }
    return OAuthIdentity(
      email: email,
      displayName: claims.name,
    );
  }

  /// Generates a PKCE code verifier and challenge.
  static ({String verifier, String challenge}) generatePkce() {
    final verifier = DfOAuthPkce.generateCodeVerifier();
    final challenge = DfOAuthPkce.generateCodeChallenge(verifier);
    return (verifier: verifier, challenge: challenge);
  }

  OAuthTokens _mapTokens(DfOAuthTokens dfTokens) {
    return OAuthTokens(
      accessToken: dfTokens.accessToken,
      refreshToken: dfTokens.refreshToken,
      expiresAt: dfTokens.expiresAt,
      idToken: dfTokens.idToken,
    );
  }
}
