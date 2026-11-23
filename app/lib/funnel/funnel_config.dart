import 'package:df_funnel/df_funnel.dart';

/// Launch funnel: onboarding, then a skippable paywall. There is deliberately
/// no login step: the app works with zero login, and the funnel's built-in login
/// screen is a placeholder that doesn't authenticate anyone. After the funnel,
/// [AppLaunchGate] sends users with no mail account to "Add Account".
class AppFunnelConfig {
  static DfFunnelConfig get config => const DfFunnelConfig(
    steps: [
      DfFunnelStep.onboarding,
      DfFunnelStep.paywall,
    ],
    loginMode: DfLoginMode.deferred,
    paywallSkippable: true,
  );
}
