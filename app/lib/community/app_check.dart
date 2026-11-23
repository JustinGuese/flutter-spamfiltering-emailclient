/// Helper to supply Firebase App Check tokens if configured on mobile platforms.
class AppCheckHelper {
  static Future<String?> getToken() async {
    // App Check is optional on desktop/unconfigured environments
    return null;
  }
}
