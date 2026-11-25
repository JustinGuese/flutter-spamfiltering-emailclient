import 'dart:io' show Platform;
import 'package:firebase_core/firebase_core.dart';

const _apiKey = String.fromEnvironment('FIREBASE_API_KEY');
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
  if (_apiKey.isEmpty || _projectId.isEmpty || appId.isEmpty) {
    return null;
  }
  return FirebaseOptions(
    apiKey: _apiKey,
    appId: appId,
    messagingSenderId: _messagingSenderId,
    projectId: _projectId,
    authDomain: _authDomain.isNotEmpty ? _authDomain : null,
  );
}
