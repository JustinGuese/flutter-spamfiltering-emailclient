import 'dart:async';
import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:df_revenuecat/df_revenuecat.dart';
import 'firebase_options_from_env.dart';
import 'platform_services.dart';

/// Native platform services implementation for iOS, Android, macOS.
/// Uses native Firebase Auth and RevenueCat.
class NativePlatformServices implements AppPlatformServices {
  @override
  bool get isDesktop => false;

  @override
  String get platformName => Platform.operatingSystem;

  @override
  bool get isFirebaseConfigured => firebaseOptionsFromEnv() != null;

  // RevenueCat issues one public SDK key per store app, so iOS/macOS and
  // Android each get their own. REVENUECAT_API_KEY is the legacy single key.
  static const _legacyKey = String.fromEnvironment('REVENUECAT_API_KEY', defaultValue: '');
  static const _iosKey = String.fromEnvironment('REVENUECAT_API_KEY_IOS', defaultValue: '');
  static const _androidKey = String.fromEnvironment('REVENUECAT_API_KEY_ANDROID', defaultValue: '');

  StreamSubscription<User?>? _authSubscription;

  @override
  Future<void> initialize() async {
    final options = firebaseOptionsFromEnv();
    if (options != null) {
      await Firebase.initializeApp(options: options);
      _authSubscription = FirebaseAuth.instance.authStateChanges().listen((user) async {
        if (user != null) {
          try {
            await DfRevenueCat.logIn(user.uid);
          } catch (_) {}
        } else {
          try {
            await DfRevenueCat.logOut();
          } catch (_) {}
        }
      });
    }

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
