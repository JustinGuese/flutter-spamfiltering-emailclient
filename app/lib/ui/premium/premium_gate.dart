import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:df_funnel/df_funnel.dart';
import 'upsell_sheet.dart';

export 'package:df_funnel/df_funnel.dart'
    show DfPremiumGate, DfProPill, DfPaywallResult;

/// Gate widget displaying [child] when the user holds Pro entitlement,
/// or an overlay prompting an upgrade.
///
/// Backed by [DfPremiumGate] from `df_funnel` wired to [dfEffectivePremiumProvider]
/// and honest pricing presentation via [AppUpsellSheet].
class AppPremiumGate extends ConsumerWidget {
  final Widget child;
  final Widget? lockedFallback;
  final String? placement;

  const AppPremiumGate({
    super.key,
    required this.child,
    this.lockedFallback,
    this.placement,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPro = ref.watch(dfEffectivePremiumProvider);

    return DfPremiumGate(
      entitlementReader: () => isPro,
      lockedBuilder: lockedFallback != null ? (_) => lockedFallback! : null,
      placement: placement ?? 'app_premium_gate',
      paywallPresenter: (ctx, {placement}) =>
          AppUpsellSheet.show(ctx, placement: placement),
      child: child,
    );
  }
}
