import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:df_oauth/df_oauth.dart';

import 'oauth_flow_loopback.dart';
import 'oauth_flow_native.dart';
import 'oauth_types.dart';

export 'oauth_types.dart';
export 'oauth_flow_loopback.dart';
export 'oauth_flow_native.dart';

/// Riverpod provider for [OAuthFlow].
final oauthFlowProvider = Provider<OAuthFlow>((ref) {
  return OAuthFlow.forPlatform();
});

/// Platform-dispatching implementation of [OAuthFlow].
class OAuthFlowPlatform implements OAuthFlow {
  final OAuthFlow _delegate;

  const OAuthFlowPlatform(this._delegate);

  /// Creates a platform-appropriate [OAuthFlow]:
  /// - Windows and Linux: [OAuthFlowLoopback] (ephemeral 127.0.0.1 HTTP server)
  /// - iOS, Android, and macOS: [OAuthFlowNative] (flutter_appauth system sheet)
  factory OAuthFlowPlatform.forPlatform({
    Duration timeout = const Duration(minutes: 3),
    DfOAuthClient? client,
    DfOAuthStrings? strings,
    DfUrlLauncher? launchUrlFn,
    DfHttpServerBinder? serverBinder,
    OAuthFlow? customFlow,
    TargetPlatform? platformOverride,
  }) {
    if (customFlow != null) {
      return OAuthFlowPlatform(customFlow);
    }

    final platform = platformOverride ?? defaultTargetPlatform;
    switch (platform) {
      case TargetPlatform.windows:
      case TargetPlatform.linux:
        return OAuthFlowPlatform(
          OAuthFlowLoopback(
            client: client,
            strings: strings,
            launchUrlFn: launchUrlFn,
            serverBinder: serverBinder,
            timeout: timeout,
          ),
        );
      case TargetPlatform.android:
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
      case TargetPlatform.fuchsia:
        return OAuthFlowPlatform(
          OAuthFlowNative(
            strings: strings,
          ),
        );
    }
  }

  @override
  Future<OAuthTokens> authorize(
    OAuthProvider p, {
    DfOAuthProviderConfig? configOverride,
  }) {
    final delegate = _delegate;
    if (delegate is OAuthFlowLoopback) {
      return delegate.authorize(
        p,
        configOverride: configOverride,
      );
    } else if (delegate is OAuthFlowNative) {
      return delegate.authorize(
        p,
        configOverride: configOverride,
      );
    }
    return delegate.authorize(p);
  }
}
