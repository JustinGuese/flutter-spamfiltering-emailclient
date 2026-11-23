import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:df_funnel/df_funnel.dart';
import 'upsell_sheet.dart';

/// Gate widget displaying [child] when the user holds Pro entitlement,
/// or an overlay prompting an upgrade.
class AppPremiumGate extends ConsumerWidget {
  final Widget child;
  final Widget? lockedFallback;

  const AppPremiumGate({
    super.key,
    required this.child,
    this.lockedFallback,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPro = ref.watch(dfEffectivePremiumProvider);

    if (isPro) {
      return child;
    }

    if (lockedFallback != null) {
      return lockedFallback!;
    }

    return DfPremiumGate(
      paywallPresenter: (ctx, {placement}) async {
        AppUpsellSheet.show(ctx);
        return DfPaywallResult.cancelled;
      },
      child: child,
    );
  }
}
