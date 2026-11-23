import 'dart:io';
import 'package:df_revenuecat/df_revenuecat.dart';
import 'package:df_firebase_auth/df_firebase_auth.dart';
import 'package:df_funnel/df_funnel.dart';
import 'package:df_billing/df_billing.dart';
import 'platform_services.dart';

/// Desktop platform services implementation for Windows and Linux.
/// Uses REST Firebase Auth and hosted checkout billing; never calls native RevenueCat.
class DesktopPlatformServices implements AppPlatformServices {
  @override
  bool get isDesktop => true;

  @override
  String get platformName => Platform.operatingSystem;

  @override
  Future<void> initialize() async {
    // Desktop initialization (no-op for native stores)
  }

  /// Provider overrides for desktop to ensure native Firebase Auth and RevenueCat
  /// are cleanly stubbed/redirected to REST / hosted billing.
  List<dynamic> get overrides => [
    dfRevenueCatIsProProvider.overrideWith((ref) => false),
    currentUserProvider.overrideWith((ref) => null),
    authStateChangesProvider.overrideWith((ref) => const Stream.empty()),
    dfEffectivePremiumProvider.overrideWith((ref) {
      return ref.watch(dfIsPremiumProvider);
    }),
  ];
}
