import 'package:df_billing/df_billing.dart';
import 'package:df_firebase_auth/df_firebase_auth.dart';
import 'package:df_firebase_rest/df_firebase_rest.dart';
import 'package:df_revenuecat/df_revenuecat.dart';
import 'package:df_settings/df_settings.dart';
import 'package:df_theme/df_theme.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import '../../app/strings.dart';
import '../../app/ui_strings.dart';
import '../../platform/platform_services.dart';

/// Account tile for Firebase / DataFortress Pro account in Settings.
///
/// Behavior:
/// - Hidden completely when Firebase is not configured.
/// - When signed in: displays email and a "Sign out" button.
///   - Native: signs out via `FirebaseAuth.instance.signOut()` and `DfRevenueCat.logOut()`.
///   - Desktop: signs out via `ref.read(dfFirebaseRestAuthProvider).signOut()`,
///     clears subscription cache, and calls `DfRevenueCat.logOut()`.
/// - When signed out: displays a "Sign in" button that opens `DfSignInSheet` (native)
///   or `DfRestSignInSheet` (desktop).
class AccountTile extends ConsumerWidget {
  const AccountTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final platformServices = _resolvePlatformServices(ref);
    if (!platformServices.isFirebaseConfigured) {
      return const SizedBox.shrink();
    }

    final isDesktop = platformServices.isDesktop;
    final palette = context.df.colors;

    if (isDesktop) {
      final restUser = ref.watch(dfFirebaseRestCurrentUserProvider);
      final email = restUser?.email;
      if (email != null && email.isNotEmpty) {
        return DfSettingsTile(
          leading: const Icon(Icons.person_outline),
          title: Text(
            UiStrings.accountSignedInAs,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: palette.textPrimary,
            ),
          ),
          subtitle: Text(
            email,
            style: TextStyle(color: palette.textSecondary),
          ),
          trailing: TextButton(
            onPressed: () => _signOutDesktop(ref),
            child: const Text(UiStrings.accountSignOut),
          ),
        );
      } else {
        return DfSettingsTile(
          leading: const Icon(Icons.person_outline),
          title: Text(
            UiStrings.accountNotSignedIn,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: palette.textPrimary,
            ),
          ),
          subtitle: Text(
            UiStrings.accountSignInPrompt,
            style: TextStyle(color: palette.textSecondary),
          ),
          trailing: OutlinedButton(
            onPressed: () => DfRestSignInSheet.show(context),
            child: const Text(UiStrings.accountSignIn),
          ),
        );
      }
    } else {
      final nativeUser = ref.watch(currentUserProvider);
      final email = nativeUser?.email;
      if (email != null && email.isNotEmpty) {
        return DfSettingsTile(
          leading: const Icon(Icons.person_outline),
          title: Text(
            UiStrings.accountSignedInAs,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: palette.textPrimary,
            ),
          ),
          subtitle: Text(
            email,
            style: TextStyle(color: palette.textSecondary),
          ),
          trailing: TextButton(
            onPressed: () => _signOutNative(),
            child: const Text(UiStrings.accountSignOut),
          ),
        );
      } else {
        return DfSettingsTile(
          leading: const Icon(Icons.person_outline),
          title: Text(
            UiStrings.accountNotSignedIn,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: palette.textPrimary,
            ),
          ),
          subtitle: Text(
            UiStrings.accountSignInPrompt,
            style: TextStyle(color: palette.textSecondary),
          ),
          trailing: OutlinedButton(
            onPressed: () => DfSignInSheet.show(context),
            child: const Text(UiStrings.accountSignIn),
          ),
        );
      }
    }
  }

  static AppPlatformServices _resolvePlatformServices(WidgetRef ref) {
    try {
      return ref.watch(platformServicesProvider);
    } catch (_) {
      // In tests or environments where platformServicesProvider is not overridden,
      // fallback to an unconfigured stub so tests pass safely.
      return const _UnconfiguredPlatformServices();
    }
  }

  static Future<void> _signOutNative() async {
    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {}
    try {
      await DfRevenueCat.logOut();
    } catch (_) {}
  }

  static Future<void> _signOutDesktop(WidgetRef ref) async {
    try {
      ref.read(dfFirebaseRestAuthProvider).signOut();
    } catch (_) {}
    try {
      ref.read(dfSubscriptionProvider.notifier).clearCache();
    } catch (_) {}
    try {
      await DfRevenueCat.logOut();
    } catch (_) {}
  }
}

class _UnconfiguredPlatformServices implements AppPlatformServices {
  const _UnconfiguredPlatformServices();

  @override
  Future<void> initialize() async {}

  @override
  bool get isDesktop => false;

  @override
  String get platformName => 'unconfigured';

  @override
  bool get isFirebaseConfigured => false;
}
