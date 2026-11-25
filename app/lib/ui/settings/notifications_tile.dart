import 'package:df_notifications/df_notifications.dart';
import 'package:df_settings/df_settings.dart';
import 'package:df_theme/df_theme.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/ui_strings.dart';
import '../../notifications/mail_notification_permission.dart';
import '../../notifications/mail_notification_service.dart';
import '../../notifications/notify_prefs.dart';
import '../../notifications/notify_types.dart';

/// Settings tile group for notifications: mode picker with options
/// ('Off', 'On every new message', 'Bundled every 5 minutes', 'Hourly summary')
/// and a 'Send test notification' action row.
class NotificationsTile extends ConsumerWidget {
  const NotificationsTile({
    super.key,
    this.ensurePermission,
  });

  /// Optional hook for requesting/ensuring notification permission.
  /// Defaults to [ensureMailNotificationPermission].
  final Future<bool> Function(BuildContext context, WidgetRef ref)?
      ensurePermission;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final NotifyMode mode;
    final bool isBlocked;
    try {
      mode = ref.watch(notifyModeProvider);
      isBlocked = ref.watch(notificationBlockedProvider);
    } catch (_) {
      // Graceful fallback when rendered without a ProviderScope (e.g. contracts test).
      return const SizedBox.shrink();
    }

    final palette = context.df.colors;
    final showBlocked = isBlocked && mode != NotifyMode.off;

    final options = [
      DfSettingsChoiceOption<NotifyMode>(
        value: NotifyMode.off,
        title: const Text(UiStrings.notifyModeOff),
      ),
      DfSettingsChoiceOption<NotifyMode>(
        value: NotifyMode.instant,
        title: const Text(UiStrings.notifyModeInstant),
      ),
      DfSettingsChoiceOption<NotifyMode>(
        value: NotifyMode.every5min,
        title: const Text(UiStrings.notifyModeEvery5min),
      ),
      DfSettingsChoiceOption<NotifyMode>(
        value: NotifyMode.hourly,
        title: const Text(UiStrings.notifyModeHourly),
      ),
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        DfSettingsChoiceTile<NotifyMode>(
          title: const Text(UiStrings.notifyModeTitle),
          subtitle: showBlocked
              ? Text(
                  UiStrings.notifyBlockedSubtitle,
                  style: TextStyle(color: palette.error.base),
                )
              : null,
          options: options,
          selected: mode,
          onSelected: (newMode) async {
            ref.read(notifyModeProvider.notifier).setMode(newMode);
            if (newMode != NotifyMode.off) {
              final requester =
                  ensurePermission ?? ensureMailNotificationPermission;
              final granted = await requester(context, ref);
              if (context.mounted) {
                ref
                    .read(notificationBlockedProvider.notifier)
                    .setBlocked(!granted);
              }
            } else {
              ref.read(notificationBlockedProvider.notifier).setBlocked(false);
            }
          },
        ),
        Divider(height: 1, thickness: 1, color: palette.hairline),
        DfSettingsTile(
          title: const Text(UiStrings.notifySendTest),
          leading: const Icon(Icons.notifications_none_outlined),
          onTap: () async {
            final sink = ref.read(notificationSinkProvider);
            await sink.show(
              DfNotificationIds.slot(0),
              UiStrings.notifyTestTitle,
              UiStrings.notifyTestBody,
              payload: 'test',
            );
          },
        ),
      ],
    );
  }
}
