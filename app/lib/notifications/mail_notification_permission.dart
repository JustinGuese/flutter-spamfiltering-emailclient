import 'package:df_notifications/df_notifications.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/ui_strings.dart';

/// Notification priming copy tailored to mail delivery.
const mailNotificationStrings = DfNotificationStrings(
  primingTitle: UiStrings.notifyPrimingTitle,
  primingBody: UiStrings.notifyPrimingBody,
  primingAcceptLabel: UiStrings.notifyPrimingAccept,
  primingDeclineLabel: UiStrings.notifyPrimingDecline,
);

/// Soft-ask permission flow using mail-specific copy instead of reminders copy.
Future<bool> ensureMailNotificationPermission(
  BuildContext context,
  WidgetRef ref,
) {
  return ensureDfNotificationPermission(
    context,
    ref,
    strings: mailNotificationStrings,
  );
}
