import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:df_funnel/df_funnel.dart';
import 'package:df_theme/df_theme.dart';
import 'funnel_config.dart';
import '../mail/account_repository.dart';
import '../ui/account_setup/account_setup_view.dart';
import '../ui/onboarding/onboarding_view.dart';
import '../ui/premium/upsell_sheet.dart';

/// Funnel entry gate wrapping the main application with skippable onboarding
/// and an optional paywall. Once the funnel is done, a user with no mail
/// account is taken straight to "Add Account".
class AppLaunchGate extends StatelessWidget {
  final Widget child;

  const AppLaunchGate({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return DfLaunchGate(
      config: AppFunnelConfig.config,
      onboardingBuilder: (ctx, onComplete) => OnboardingView(onComplete: onComplete),
      // The funnel mounts the paywall as a full page, not inside a bottom
      // sheet, so it needs its own Material surface (otherwise: black canvas
      // and yellow-underlined text).
      paywallBuilder: (ctx, onComplete) => Scaffold(
        backgroundColor: ctx.df.colors.canvas,
        body: AppUpsellSheet(
          onDismiss: onComplete,
          onSubscribed: onComplete,
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
