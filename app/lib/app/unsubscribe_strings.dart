/// Centralized user-facing strings for the unsubscribe flow.
/// Kept in its own file to avoid merge conflicts with parallel branches.
abstract final class UnsubscribeStrings {
  // Settings
  static const settingTitle = 'Auto-unsubscribe';
  static const settingSubtitle =
      'Automatically unsubscribe when marking an email as spam';

  // Reader actions & status
  static const buttonLabel = 'Unsubscribe';
  static String unsubscribedFrom(String domain) => 'Unsubscribed from $domain';
  static const unsubscribed = 'Unsubscribed';
  static const failed = "Couldn't unsubscribe";
  static const inProgress = 'Unsubscribing…';
}
