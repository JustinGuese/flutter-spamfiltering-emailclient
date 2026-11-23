import 'dart:io';
import 'package:df_revenuecat/df_revenuecat.dart';
import 'platform_services.dart';

/// Native platform services implementation for iOS, Android, macOS.
/// Uses native Firebase Auth and RevenueCat.
class NativePlatformServices implements AppPlatformServices {
  @override
  bool get isDesktop => false;

  @override
  String get platformName => Platform.operatingSystem;

  @override
  Future<void> initialize() async {
    const apiKey = String.fromEnvironment('REVENUECAT_API_KEY', defaultValue: '');
    if (apiKey.isNotEmpty) {
      await DfRevenueCat.initialize(
        config: const DfRevenueCatConfig(
          iosApiKey: apiKey,
          androidApiKey: apiKey,
          entitlementId: 'pro',
        ),
      );
    }
  }

  /// Provider overrides specific to native platforms.
  List<dynamic> get overrides => [];
}
