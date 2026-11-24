import 'package:df_oauth/df_oauth.dart';
import 'package:flutter/foundation.dart';

import 'oauth_flow.dart';

enum OAuthProvider { google, microsoft }

class OAuthTokens {
  final String accessToken;
  final String? refreshToken;
  final DateTime expiresAt;
  final String? idToken;

  const OAuthTokens({
    required this.accessToken,
    this.refreshToken,
    required this.expiresAt,
    this.idToken,
  });
}

class OAuthIdentity {
  final String email;
  final String? displayName;

  const OAuthIdentity({required this.email, this.displayName});
}

class ReauthRequiredException implements Exception {
  final String accountId;
  final String email;
  final OAuthProvider provider;

  const ReauthRequiredException({
    required this.accountId,
    required this.email,
    required this.provider,
  });

  @override
  String toString() =>
      'ReauthRequiredException(accountId: $accountId, email: $email, provider: $provider)';
}

/// Thrown when an OAuth provider's client ID is not configured in the build environment.
class OAuthNotConfiguredException implements Exception {
  final OAuthProvider provider;

  const OAuthNotConfiguredException(this.provider);

  @override
  String toString() =>
      'OAuthNotConfiguredException: Client ID is not configured for $provider';
}

/// Thrown when the user cancels the interactive OAuth flow.
class OAuthCancelledException implements Exception {
  final String? message;

  const OAuthCancelledException([this.message]);

  @override
  String toString() =>
      'OAuthCancelledException: ${message ?? "Sign-in was cancelled by the user"}';
}

/// Interactive OAuth authorization flow contract.
abstract class OAuthFlow {
  /// Prompts the user to authorize access and returns [OAuthTokens].
  Future<OAuthTokens> authorize(OAuthProvider p);

  /// Factory constructor to create a platform-appropriate [OAuthFlow].
  /// On Windows and Linux, returns a loopback flow ([OAuthFlowLoopback]).
  /// On iOS, Android, and macOS, returns a native AppAuth flow ([OAuthFlowNative]).
  factory OAuthFlow.forPlatform({
    Duration timeout,
    DfOAuthClient? client,
    DfOAuthStrings? strings,
    DfUrlLauncher? launchUrlFn,
    DfHttpServerBinder? serverBinder,
    OAuthFlow? customFlow,
    TargetPlatform? platformOverride,
  }) = OAuthFlowPlatform.forPlatform;
}
