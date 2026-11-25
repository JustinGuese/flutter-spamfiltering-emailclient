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

  // RevenueCat issues one public SDK key per store app, so iOS/macOS and
  // Android each get their own. REVENUECAT_API_KEY is the legacy single key.
  static const _legacyKey = String.fromEnvironment('REVENUECAT_API_KEY', defaultValue: '');
  static const _iosKey = String.fromEnvironment('REVENUECAT_API_KEY_IOS', defaultValue: '');
  static const _androidKey = String.fromEnvironment('REVENUECAT_API_KEY_ANDROID', defaultValue: '');

  @override
  Future<void> initialize() async {
    final ios = _iosKey.isNotEmpty ? _iosKey : _legacyKey;
    final android = _androidKey.isNotEmpty ? _androidKey : _legacyKey;
    final active = Platform.isAndroid ? android : ios;
    if (active.isEmpty) return;
    await DfRevenueCat.initialize(
      config: DfRevenueCatConfig(
        iosApiKey: ios,
        androidApiKey: android,
        entitlementId: 'pro',
      ),
    );
  }

  /// Provider overrides specific to native platforms.
  List<dynamic> get overrides => [];
}
