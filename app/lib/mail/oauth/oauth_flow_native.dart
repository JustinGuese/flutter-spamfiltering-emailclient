import 'package:df_oauth/df_oauth.dart';

import 'oauth_config.dart';
import 'oauth_types.dart';

/// Mobile and macOS OAuth2 authorization flow using AppAuth system browser sheet.
///
/// Uses ASWebAuthenticationSession on iOS/macOS and Custom Tabs on Android with PKCE.
class OAuthFlowNative implements OAuthFlow {
  final DfOAuthAppAuthFlow _flow;

  OAuthFlowNative({
    DfOAuthStrings? strings,
    DfOAuthAppAuthFlow? flowOverride,
  }) : _flow = flowOverride ??
            DfOAuthAppAuthFlow(
              strings: strings,
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
