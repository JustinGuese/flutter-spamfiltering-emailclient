import 'dart:io';

import 'package:df_billing/df_billing.dart';
import 'package:df_funnel/df_funnel.dart';
import 'package:df_revenuecat/df_revenuecat.dart'
    show DfPaywallLauncher, DfRevenueCat;
import 'package:flutter/widgets.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/ui_strings.dart';
import '../../platform/desktop_services.dart';
import '../../platform/firebase_options_from_env.dart' as env_opts;
import 'app_auth_gate.dart';

/// Function signature for launching the paywall.
typedef DfPaywallLauncherFn = Future<DfPaywallResult> Function(
  BuildContext context, {
  String? placement,
});

/// Function signature for opening the web purchase link.
typedef DfWebLinkOpenerFn = Future<DfCheckoutResult> Function({
  required String? baseLink,
  required String? appUserId,
  String? email,
});

/// Starts a real subscription flow for "Upgrade to Pro".
///
/// Flow:
/// 1. Check if Firebase is configured. If not configured, show snackbar
///    and return [DfPaywallResult.notPresented].
/// 2. Check sign-in status (via [AppAuthGate.ensureSignedIn]).
///    If cancelled / dismissed (returned null): return [DfPaywallResult.cancelled]
///    without showing purchase UI!
/// 3. If signed in with `uid`:
///    - Native: await [DfRevenueCat.logIn(uid)], then return await
///      [DfPaywallLauncher.show(context, placement: placement ?? 'app_upsell')].
///      If error / notPresented, show snackbar.
///    - Desktop: get `RC_WEB_PURCHASE_LINK` (from DesktopPlatformServices define).
///      Call [DfWebPurchaseLink.open(baseLink: rcWebPurchaseLink, appUserId: uid)].
///      Return [DfPaywallResult.notPresented] (entitlement arrives through fetcher
///      on resume — NEVER report purchased from browser launch).
///      If open fails (e.g. notConfigured / launchFailed), show snackbar.
abstract final class AppCheckout {
  /// Test seam: replaces the platform flow entirely.
  @visibleForTesting
  static DfPaywallPresenter? debugPresenter;

  /// Test seam: force the desktop branch on or off.
  @visibleForTesting
  static bool? debugIsDesktop;

  /// Test seam: force isFirebaseConfigured check.
  @visibleForTesting
  static bool? debugIsFirebaseConfigured;

  /// Test seam: override auth gate ensureSignedIn.
  @visibleForTesting
  static AppAuthGateEnsurer? debugAuthGate;

  /// Test seam: override native paywall launcher.
  @visibleForTesting
  static DfPaywallLauncherFn? debugLauncher;

  /// Test seam: override desktop web link opener.
  @visibleForTesting
  static DfWebLinkOpenerFn? debugWebLinkOpener;

  /// Test seam: override desktop web purchase link base.
  @visibleForTesting
  static String? debugRcWebPurchaseLink;

  /// Test seam: override native DfRevenueCat.logIn.
  @visibleForTesting
  static Future<dynamic> Function(String uid)? debugRevenueCatLogIn;

  static bool get _isDesktop =>
      debugIsDesktop ?? (Platform.isWindows || Platform.isLinux);

  static bool get _isFirebaseConfigured {
    if (debugIsFirebaseConfigured != null) {
      return debugIsFirebaseConfigured!;
    }
    if (_isDesktop) {
      return DesktopPlatformServices.webApiKey.isNotEmpty;
    } else {
      return env_opts.isFirebaseConfigured;
    }
  }

  static String get _rcWebPurchaseLink =>
      debugRcWebPurchaseLink ?? DesktopPlatformServices.rcWebPurchaseLink;

  static Future<DfPaywallResult> present(
    BuildContext context, {
    String? placement,
  }) async {
    final override = debugPresenter;
    if (override != null) return override(context, placement: placement);

    // 1. Check if Firebase is configured
    if (!_isFirebaseConfigured) {
      if (context.mounted) {
        _tell(context, UiStrings.checkoutUnavailable);
      }
      return DfPaywallResult.notPresented;
    }

    // 2. Check sign-in status (ensureSignedIn)
    final uid = debugAuthGate != null
        ? await debugAuthGate!(context)
        : await AppAuthGate.ensureSignedIn(context);

    if (uid == null || uid.isEmpty) {
      return DfPaywallResult.cancelled;
    }

    // 3. If signed in with uid:
    if (_isDesktop) {
      final baseLink = _rcWebPurchaseLink;
      final opener = debugWebLinkOpener ?? DfWebPurchaseLink.open;
      final res = await opener(
        baseLink: baseLink,
        appUserId: uid,
      );

      if (!res.isSuccess && context.mounted) {
        _tell(context, UiStrings.checkoutUnavailable);
      }

      // Entitlement arrives through the fetcher on resume —
      // NEVER report purchased from browser launch!
      return DfPaywallResult.notPresented;
    } else {
      if (debugRevenueCatLogIn != null) {
        await debugRevenueCatLogIn!(uid);
      } else {
        await DfRevenueCat.logIn(uid);
      }

      final launcher = debugLauncher ?? DfPaywallLauncher.show;
      final result = await launcher(
        context,
        placement: placement ?? 'app_upsell',
      );

      if (context.mounted &&
          (result == DfPaywallResult.error ||
              result == DfPaywallResult.notPresented)) {
        _tell(context, UiStrings.checkoutUnavailable);
      }
      return result;
    }
  }

  static void _tell(BuildContext context, String message) {
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}
