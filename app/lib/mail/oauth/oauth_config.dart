import 'dart:io';
import 'package:df_oauth/df_oauth.dart';
import 'oauth_types.dart';

/// OAuth configuration helper for mail providers (Google and Microsoft).
///
/// Reads client IDs and secrets from compile-time environment variables:
/// - `GOOGLE_OAUTH_CLIENT_ID_IOS`
/// - `GOOGLE_OAUTH_CLIENT_ID_ANDROID`
/// - `GOOGLE_OAUTH_CLIENT_ID_DESKTOP`
/// - `GOOGLE_OAUTH_CLIENT_SECRET_DESKTOP`
/// - `MS_OAUTH_CLIENT_ID`
class OAuthConfig {
  static const String googleClientIdIos =
      String.fromEnvironment('GOOGLE_OAUTH_CLIENT_ID_IOS');
  static const String googleClientIdAndroid =
      String.fromEnvironment('GOOGLE_OAUTH_CLIENT_ID_ANDROID');
  static const String googleClientIdDesktop =
      String.fromEnvironment('GOOGLE_OAUTH_CLIENT_ID_DESKTOP');
  static const String googleClientSecretDesktop =
      String.fromEnvironment('GOOGLE_OAUTH_CLIENT_SECRET_DESKTOP');

  static const String msClientId =
      String.fromEnvironment('MS_OAUTH_CLIENT_ID');

  /// Google Mail OAuth scopes.
  /// Needs `https://mail.google.com/` for full IMAP/SMTP access.
  static const List<String> googleScopes = [
    'https://mail.google.com/',
    'openid',
    'email',
    'profile',
  ];

  /// Microsoft Outlook OAuth scopes.
  /// Needs IMAP.AccessAsUser.All and SMTP.Send for mail protocols.
  static const List<String> microsoftScopes = [
    'https://outlook.office.com/IMAP.AccessAsUser.All',
    'https://outlook.office.com/SMTP.Send',
    'offline_access',
    'openid',
    'email',
    'profile',
  ];

  /// Application package/bundle ID for custom scheme redirects.
  static const String bundleId = 'com.datafortress.spamfilteringemailclient';

  /// Determines the Google Client ID appropriate for the current platform.
  static String getGoogleClientId() {
    if (Platform.isIOS) {
      return googleClientIdIos;
    } else if (Platform.isAndroid) {
      return googleClientIdAndroid;
    } else {
      return googleClientIdDesktop;
    }
  }

  /// Determines the Google Client Secret (only needed on Desktop/loopback flow).
  static String? getGoogleClientSecret() {
    if (Platform.isAndroid || Platform.isIOS) {
      return null;
    }
    return googleClientSecretDesktop.isNotEmpty
        ? googleClientSecretDesktop
        : null;
  }

  /// Calculates the redirect URI for Google OAuth on the current platform.
  static String getGoogleRedirectUri({String? clientId}) {
    if (Platform.isAndroid) {
      return '$bundleId:/oauth2redirect';
    } else if (Platform.isIOS) {
      final id = clientId ?? getGoogleClientId();
      if (id.isNotEmpty && id.contains('.')) {
        // iOS Google OAuth redirect is the reversed client ID: e.g. com.googleusercontent.apps.XYZ:/oauth2redirect
        final parts = id.split('.');
        final reversed = parts.reversed.join('.');
        return '$reversed:/oauth2redirect';
      }
      return '$bundleId:/oauth2redirect';
    } else {
      // Loopback on desktop (port 0 / dynamic loopback handled by loopback flow)
      return 'http://127.0.0.1';
    }
  }

  /// Calculates the redirect URI for Microsoft OAuth on the current platform.
  static String getMicrosoftRedirectUri() {
    if (Platform.isAndroid) {
      return 'msauth://$bundleId/oauth2redirect';
    } else if (Platform.isIOS) {
      return 'msauth.$bundleId://auth';
    } else {
      return 'http://127.0.0.1';
    }
  }

  /// Builds a [DfOAuthProviderConfig] for the given [OAuthProvider].
  static DfOAuthProviderConfig forProvider(
    OAuthProvider provider, {
    String? customClientId,
    String? customClientSecret,
    String? customRedirectUri,
  }) {
    switch (provider) {
      case OAuthProvider.google:
        final clientId = customClientId ?? getGoogleClientId();
        final clientSecret = customClientSecret ?? getGoogleClientSecret();
        final redirectUri =
            customRedirectUri ?? getGoogleRedirectUri(clientId: clientId);

        return DfOAuthProviderConfig.google(
          clientId: clientId,
          clientSecret: clientSecret,
          redirectUri: redirectUri,
          scopes: googleScopes,
        );

      case OAuthProvider.microsoft:
        final clientId = customClientId ?? msClientId;
        final clientSecret = customClientSecret;
        final redirectUri = customRedirectUri ?? getMicrosoftRedirectUri();

        return DfOAuthProviderConfig.microsoft(
          clientId: clientId,
          clientSecret: clientSecret,
          redirectUri: redirectUri,
          tenant: 'common',
          scopes: microsoftScopes,
        );
    }
  }

  /// Returns true if the client ID for [provider] is configured in this build.
  static bool isConfigured(OAuthProvider provider) {
    switch (provider) {
      case OAuthProvider.google:
        return getGoogleClientId().isNotEmpty;
      case OAuthProvider.microsoft:
        return msClientId.isNotEmpty;
    }
  }
}
