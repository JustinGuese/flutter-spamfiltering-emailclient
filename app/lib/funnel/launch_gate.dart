import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:df_funnel/df_funnel.dart';
import 'package:df_onboarding/df_onboarding.dart';
import 'package:df_theme/df_theme.dart';
import 'funnel_config.dart';
import '../app/strings.dart';
import '../mail/account_repository.dart';
import '../ui/account_setup/account_setup_view.dart';
import '../ui/premium/app_upsell.dart';

/// Funnel entry gate wrapping the main application with skippable onboarding
/// and an optional paywall. Once the funnel is done, a user with no mail
/// account is taken straight to "Add Account".
class AppLaunchGate extends StatelessWidget {
  final Widget child;

  const AppLaunchGate({super.key, required this.child});

  static Widget buildOnboarding(BuildContext context, VoidCallback onComplete) {
    final c = context.df.colors;
    return ProviderScope(
      overrides: [
        onboardingConfigProvider.overrideWithValue(
          OnboardingConfig(
            showSkipButton: true,
            preferencesKey: AppFunnelConfig.config.onboardingCompletedKey,
            pages: [
              OnboardingPageModel(
                icon: Icons.lock_outline_rounded,
                emoji: '🔒',
                title: AppStrings.onbPage1Title,
                subtitle: AppStrings.onbPage1Body,
                features: const [
                  'Private by design',
                  'Absolute local privacy',
                  'Zero tracking or ad networks',
                ],
                gradient: [c.brand.deep, c.brand.base],
              ),
              OnboardingPageModel(
                icon: Icons.psychology_outlined,
                emoji: '⚡',
                title: AppStrings.onbPage2Title,
                subtitle: AppStrings.onbPage2Body,
                features: const [
                  'Learns on-device',
                  'Bayesian token classification',
                  'Data never leaves your disk',
                ],
                gradient: [c.brand.base, c.accent.deep],
              ),
              OnboardingPageModel(
                icon: Icons.shield_outlined,
                emoji: '🛡️',
                title: AppStrings.onbPage3Title,
                subtitle: AppStrings.onbPage3Body,
                features: const [
                  'Community protection',
                  'Zero-ID anonymous hashes',
                  'Block emerging spam campaigns',
                ],
                gradient: [c.accent.deep, c.brand.deep],
              ),
            ],
          ),
        ),
      ],
      child: OnboardingScreen(
        onNavigateAfterComplete: onComplete,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DfLaunchGate(
      config: AppFunnelConfig.config,
      onboardingBuilder: (ctx, onComplete) => buildOnboarding(ctx, onComplete),
      // The funnel mounts the paywall as a full page, not inside a bottom
      // sheet, so it needs its own Material surface (otherwise: black canvas
      // and yellow-underlined text).
      paywallBuilder: (ctx, onComplete) => Scaffold(
        backgroundColor: ctx.df.colors.canvas,
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: AppUpsell.buildSheet(
              popOnCta: false,
              onDismiss: onComplete,
              onCta: onComplete,
            ),
          ),
        ),
      ),
      // DfLaunchGate only mounts this once the funnel is complete.
      child: _AddAccountRedirect(child: child),
    );
  }
}

/// Pushes the account setup screen once when the app shell first appears with
/// no accounts. Backing out is allowed (Settings keeps an "Add Account"
/// entry), so this does not nag again until the next launch.
class _AddAccountRedirect extends ConsumerStatefulWidget {
  final Widget child;

  const _AddAccountRedirect({required this.child});

  @override
  ConsumerState<_AddAccountRedirect> createState() => _AddAccountRedirectState();
}

class _AddAccountRedirectState extends ConsumerState<_AddAccountRedirect> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (ref.read(accountRepositoryProvider).listAccounts().isNotEmpty) return;
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const AccountSetupView()),
      );
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
