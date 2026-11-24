import 'dart:async';
import 'package:df_notifications/df_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'notify_types.dart';

/// Notification channel dedicated to new email alerts.
const kMailNotificationChannel = DfNotificationChannel(
  id: 'mail_new',
  name: 'New mail',
  description: 'Notifications for incoming emails',
  importance: DfNotificationImportance.high,
);

/// Adapter implementing [NotificationSink] on top of [DfReminderService].
///
/// Routes immediate notifications to [DfReminderService.show] with the
/// email channel [kMailNotificationChannel], while delegating standard
/// lifecycle, scheduling, and payload consumption.
class MailNotificationService implements DfReminderService, NotificationSink {
  MailNotificationService({this._reminderService});

  DfReminderService? _reminderService;

  DfReminderService get _service =>
      _reminderService ??= DfReminderService();

  @override
  Future<void> init() => _service.init();

  @override
  Future<bool> requestPermission() => _service.requestPermission();

  @override
  Future<void> schedule(DfReminder reminder) => _service.schedule(reminder);

  @override
  Future<void> cancel(int id) => _service.cancel(id);

  @override
  Future<void> cancelMany(Iterable<int> ids) => _service.cancelMany(ids);

  @override
  String? consumePendingPayload() => _service.consumePendingPayload();

  @override
  Future<void> show(
    int id,
    String title,
    String body, {
    DfNotificationChannel channel = kMailNotificationChannel,
    String? payload,
  }) async {
    await _service.show(
      id,
      title,
      body,
      channel: channel,
      payload: payload,
    );
  }
}

/// Riverpod provider exposing [MailNotificationService] (also usable as [NotificationSink]).
final mailNotificationServiceProvider = Provider<MailNotificationService>((ref) {
  final reminderService = ref.watch(dfReminderServiceProvider);
  return MailNotificationService(reminderService: reminderService);
});

/// Riverpod provider exposing [NotificationSink].
final notificationSinkProvider = Provider<NotificationSink>((ref) {
  return ref.watch(mailNotificationServiceProvider);
});
