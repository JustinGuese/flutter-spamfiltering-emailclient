import 'dart:io';
import 'package:df_firebase_auth/df_firebase_auth.dart';
import 'package:df_firebase_rest/df_firebase_rest.dart';
import 'package:firebase_auth/firebase_auth.dart' as native_auth;
import 'package:flutter/widgets.dart';

/// Test seam for mocking sign-in gate in tests.
typedef AppAuthGateEnsurer = Future<String?> Function(BuildContext context);

/// Checks sign-in status and presents the platform-appropriate sign-in sheet
/// if not already signed in.
abstract final class AppAuthGate {
  /// Test seam: replaces [ensureSignedIn] entirely.
  @visibleForTesting
  static AppAuthGateEnsurer? debugEnsurer;

  /// Test seam: force desktop branch on or off.
  @visibleForTesting
  static bool? debugIsDesktop;

  /// Test seam: override native User check.
  @visibleForTesting
  static native_auth.User? Function()? debugNativeUser;

  /// Test seam: override desktop REST User check.
  @visibleForTesting
  static FirebaseRestUser? Function(BuildContext context)? debugDesktopUser;

  /// Test seam: override native sign-in sheet launcher.
  @visibleForTesting
  static Future<dynamic> Function(BuildContext context)? debugNativeSignInSheet;

  /// Test seam: override desktop REST sign-in sheet launcher.
  @visibleForTesting
  static Future<FirebaseRestUser?> Function(BuildContext context)? debugDesktopSignInSheet;

  static bool get _isDesktop =>
      debugIsDesktop ?? (Platform.isWindows || Platform.isLinux);

  /// Ensures the user is signed in, prompting with the platform sheet if not.
  ///
  /// Returns the signed-in user's `uid`, or `null` if cancelled or dismissed.
  static Future<String?> ensureSignedIn(BuildContext context) async {
    final override = debugEnsurer;
    if (override != null) {
      return override(context);
    }

    if (_isDesktop) {
      return _ensureDesktopSignedIn(context);
    } else {
      return _ensureNativeSignedIn(context);
    }
  }

  static Future<String?> _ensureNativeSignedIn(BuildContext context) async {
    // 1. Check if already signed in
    if (debugNativeUser != null) {
      final user = debugNativeUser!();
      if (user != null && user.uid.isNotEmpty) return user.uid;
    } else {
      final user = native_auth.FirebaseAuth.instance.currentUser;
      if (user != null && user.uid.isNotEmpty) return user.uid;
    }

    // 2. Prompt using shared native sheet
    if (debugNativeSignInSheet != null) {
      final res = await debugNativeSignInSheet!(context);
      if (res is native_auth.User) return res.uid;
      if (res is String && res.isNotEmpty) return res;
      if (res == true) {
        // Sheet popped with true, check currentUser
        final u = debugNativeUser != null
            ? debugNativeUser!()
            : native_auth.FirebaseAuth.instance.currentUser;
        return u?.uid;
      }
      return null;
    }

    final res = await DfSignInSheet.show(context);
    if (res is native_auth.User) return res.uid;
    if (res is String && res.isNotEmpty) return res;
    if (res == true) {
      final u = native_auth.FirebaseAuth.instance.currentUser;
      return u?.uid;
    }
    final u = native_auth.FirebaseAuth.instance.currentUser;
    return u?.uid;
  }

  static Future<String?> _ensureDesktopSignedIn(BuildContext context) async {
    // 1. Check if already signed in
    if (debugDesktopUser != null) {
      final user = debugDesktopUser!(context);
      if (user != null && user.uid.isNotEmpty) return user.uid;
    }

    // 2. Prompt using shared REST sheet
    if (debugDesktopSignInSheet != null) {
      final user = await debugDesktopSignInSheet!(context);
      return user?.uid;
    }

    final user = await DfRestSignInSheet.show(context);
    return user?.uid;
  }
}
