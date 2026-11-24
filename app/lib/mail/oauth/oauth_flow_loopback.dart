import 'package:df_oauth/df_oauth.dart';

import 'oauth_config.dart';
import 'oauth_types.dart';

/// Desktop OAuth2 authorization flow (Windows & Linux) using an ephemeral loopback HTTP server.
///
/// Security characteristics:
/// - Strictly binds only to IPv4 loopback (`127.0.0.1`), never external interfaces.
/// - Validates cryptographically secure state parameter on callback.
/// - RFC 7636 PKCE S256 code challenge and verifier.
/// - Closes loopback server immediately after the first callback or timeout.
/// - Returns user-friendly status HTML to the browser.
class OAuthFlowLoopback implements OAuthFlow {
  final DfOAuthLoopbackFlow _flow;

  OAuthFlowLoopback({
    DfOAuthClient? client,
    DfOAuthStrings? strings,
    DfUrlLauncher? launchUrlFn,
    DfHttpServerBinder? serverBinder,
    Duration timeout = const Duration(minutes: 3),
    DfOAuthLoopbackFlow? flowOverride,
  }) : _flow = flowOverride ??
            DfOAuthLoopbackFlow(
              client: client,
              strings: strings,
              launchUrlFn: launchUrlFn,
              serverBinder: serverBinder,
              timeout: timeout,
            );

  @override
  Future<OAuthTokens> authorize(
    OAuthProvider p, {
    DfOAuthProviderConfig? configOverride,
  }) async {
    if (configOverride != null
        ? configOverride.clientId.isEmpty
        : !OAuthConfig.isConfigured(p)) {
      throw OAuthNotConfiguredException(p);
    }

    final config = configOverride ?? OAuthConfig.forProvider(p);
    try {
      final dfTokens = await _flow.authorize(config);
      return OAuthTokens(
        accessToken: dfTokens.accessToken,
        refreshToken: dfTokens.refreshToken,
        expiresAt: dfTokens.expiresAt,
        idToken: dfTokens.idToken,
      );
    } on DfOAuthCancelledException catch (e) {
      throw OAuthCancelledException(e.message);
    }
  }
}
