import 'dart:io' show Platform;
import 'package:firebase_core/firebase_core.dart';

// Firebase issues one API key per platform app. FIREBASE_API_KEY is the single-key fallback.
const _apiKeyLegacy = String.fromEnvironment('FIREBASE_API_KEY');
const _apiKeyAndroid = String.fromEnvironment('FIREBASE_API_KEY_ANDROID');
const _apiKeyIos = String.fromEnvironment('FIREBASE_API_KEY_IOS');
const _appIdAndroid = String.fromEnvironment('FIREBASE_APP_ID_ANDROID');
const _appIdIos = String.fromEnvironment('FIREBASE_APP_ID_IOS');
const _projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
const _messagingSenderId = String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
const _authDomain = String.fromEnvironment('FIREBASE_AUTH_DOMAIN');

/// Whether Firebase has enough configuration in the environment to initialize.
bool get isFirebaseConfigured => firebaseOptionsFromEnv() != null;

/// Constructs [FirebaseOptions] from environment variables, or returns `null`
/// if required options are not provided.
FirebaseOptions? firebaseOptionsFromEnv() {
  final appId = Platform.isAndroid ? _appIdAndroid : _appIdIos;
  final platformKey = Platform.isAndroid ? _apiKeyAndroid : _apiKeyIos;
  final apiKey = platformKey.isNotEmpty ? platformKey : _apiKeyLegacy;
  if (apiKey.isEmpty || _projectId.isEmpty || appId.isEmpty) {
    return null;
  }
  return FirebaseOptions(
    apiKey: apiKey,
    appId: appId,
    messagingSenderId: _messagingSenderId,
    projectId: _projectId,
    authDomain: _authDomain.isNotEmpty ? _authDomain : null,
  );
}
