import 'package:flutter/foundation.dart';

/// Prints an error with its stack trace to the console. Failures that the app
/// handles (a sync that fails, a best-effort call that is skipped) must still
/// be visible when running `flutter run`, never swallowed silently.
void logError(String where, Object error, [StackTrace? stack]) {
  debugPrint('[error] $where: $error');
  if (stack != null) debugPrint(stack.toString());
}

/// Progress line for the console, e.g. `[sync] connecting to imap.gmail.com`.
void logInfo(String tag, String message) => debugPrint('[$tag] $message');
