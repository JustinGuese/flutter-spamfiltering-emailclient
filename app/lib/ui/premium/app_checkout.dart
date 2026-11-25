import 'dart:io';

import 'package:df_funnel/df_funnel.dart';
import 'package:df_revenuecat/df_revenuecat.dart' show DfPaywallLauncher;
import 'package:material_ui/material_ui.dart';

import '../../app/ui_strings.dart';

/// Starts a real subscription flow for "Upgrade to Pro".
///
/// - iOS / Android / macOS: the RevenueCat paywall via [DfPaywallLauncher]
///   (needs the platform's RevenueCat key; without it the launcher reports
///   [DfPaywallResult.error]).
/// - Windows / Linux: there is no in-app checkout yet (hosted Stripe checkout
///   needs payment links and a signed-in user id this client does not have).
///
/// Never reports [DfPaywallResult.purchased] unless the store said so. When
/// nothing could be shown, the user gets a snackbar instead of a dead button.
abstract final class AppCheckout {
  /// Test seam: replaces the platform flow entirely.
  @visibleForTesting
  static DfPaywallPresenter? debugPresenter;

  /// Test seam: force the desktop branch on or off.
  @visibleForTesting
  static bool? debugIsDesktop;

  static bool get _isDesktop =>
      debugIsDesktop ?? (Platform.isWindows || Platform.isLinux);

  static Future<DfPaywallResult> present(
    BuildContext context, {
    String? placement,
  }) async {
    final override = debugPresenter;
    if (override != null) return override(context, placement: placement);

    if (_isDesktop) {
      _tell(context, UiStrings.checkoutDesktopUnavailable);
      return DfPaywallResult.notPresented;
    }

    final result = await DfPaywallLauncher.show(
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

  static void _tell(BuildContext context, String message) {
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}
