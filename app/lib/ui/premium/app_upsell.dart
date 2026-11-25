import 'dart:async';

import 'package:df_funnel/df_funnel.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/strings.dart';
import '../../app/ui_strings.dart';
import 'app_checkout.dart';

/// App-specific configuration and entry points for [DfUpsellSheet].
///
/// Adheres strictly to honest pricing guidelines:
/// - Price and renewal terms clearly visible
/// - Equal prominence close and dismiss actions
/// - Zero fake timers or dark patterns
class AppUpsell {
  static const String defaultCooldownKey = 'df_upsell_sheet_cooldown';
  static const Duration defaultCooldownDuration = Duration(hours: 24);

  static const perks = [
    DfPerkItem(
      icon: Icons.sync_rounded,
      title: '',
      body: UiStrings.upsellPoint1,
    ),
    DfPerkItem(
      icon: Icons.devices_rounded,
      title: '',
      body: UiStrings.upsellPoint2,
    ),
    DfPerkItem(
      icon: Icons.lock_outline_rounded,
      title: '',
      body: UiStrings.upsellPoint3,
    ),
    DfPerkItem(
      icon: Icons.key_rounded,
      title: '',
      body: UiStrings.upsellPoint4,
    ),
  ];

  static const plan = DfUpsellPlan(
    name: UiStrings.upsellAnnual,
    price: AppStrings.proAnnual,
    renewalNote: UiStrings.upsellRenewal,
  );

  /// Builds a [DfUpsellSheet] widget configured with DataFortress Mail's honest pricing copy.
  static Widget buildSheet({
    VoidCallback? onDismiss,
    VoidCallback? onCta,
    bool popOnCta = true,
    String? placement,
  }) {
    return DfUpsellSheet(
      placement: placement ?? 'app_upsell',
      headline: UiStrings.upsellHeadline,
      subtitle: UiStrings.upsellSub,
      footnote: UiStrings.upsellFreeNote,
      ctaLabel: AppStrings.proUpgrade,
      perks: perks,
      plan: plan,
      dismissStyle: DfUpsellDismissStyle.equalButton,
      showCloseButton: true,
      popOnCta: popOnCta,
      onDismiss: onDismiss,
      onCta: onCta,
    );
  }

  /// Displays the honest upsell sheet modally. Returns the real checkout
  /// result ([AppCheckout]); dismissing returns [DfPaywallResult.cancelled].
  static Future<DfPaywallResult> show(
    BuildContext context, {
    String? placement,
  }) {
    return DfUpsellSheet.show(
      context,
      placement: placement ?? 'feed_sheet',
      headline: UiStrings.upsellHeadline,
      subtitle: UiStrings.upsellSub,
      footnote: UiStrings.upsellFreeNote,
      ctaLabel: AppStrings.proUpgrade,
      perks: perks,
      plan: plan,
      dismissStyle: DfUpsellDismissStyle.equalButton,
      showCloseButton: true,
      paywallPresenter: AppCheckout.present,
    );
  }

  /// Shows the upsell sheet if [cooldown] is ready.
  ///
  /// Returns `true` if shown, or `false` if blocked by cooldown.
  static Future<bool> maybeShow(
    BuildContext context, {
    DfCooldown cooldown = const DfCooldown(
      key: defaultCooldownKey,
      duration: defaultCooldownDuration,
    ),
    dynamic prefs,
    String? placement,
  }) {
    return DfUpsellSheet.maybeShow(
      context,
      cooldown: cooldown,
      prefs: prefs,
      placement: placement ?? 'feed_sheet',
      headline: UiStrings.upsellHeadline,
      subtitle: UiStrings.upsellSub,
      footnote: UiStrings.upsellFreeNote,
      ctaLabel: AppStrings.proUpgrade,
      perks: perks,
      plan: plan,
      dismissStyle: DfUpsellDismissStyle.equalButton,
      showCloseButton: true,
      paywallPresenter: AppCheckout.present,
    );
  }
}
