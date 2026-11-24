import 'dart:async';
import 'package:df_notifications/df_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../app/ui_strings.dart';
import 'mail_notification_service.dart';
import 'notify_prefs.dart';
import 'notify_types.dart';

/// Pure Dart notifier that buffers and dispatches incoming new mail notifications
/// according to the selected [NotifyMode].
///
/// Lock-screen privacy: titles/bodies contain sender + subject only, never body text.
class NewMailNotifier {
  final NotificationSink sink;
  final DateTime Function() _clock;
  NotifyMode mode;

  final List<NewMail> _pending = [];
  DateTime? _lastFlushTime;
  int _ringSlotIndex = 0;

  NewMailNotifier({
    required this.sink,
    DateTime Function()? clock,
    this.mode = NotifyMode.instant,
  }) : _clock = clock ?? DateTime.now;

  /// The list of currently buffered messages pending notification.
  List<NewMail> get pending => List.unmodifiable(_pending);

  /// The timestamp when the last notification flush took place.
  DateTime? get lastFlushTime => _lastFlushTime;

  /// Adds newly received messages to the buffer.
  void add(List<NewMail> mail) {
    if (mode == NotifyMode.off || mail.isEmpty) return;
    _pending.addAll(mail);
  }

  /// Flushes pending notifications based on [mode].
  Future<void> flush() async {
    if (mode == NotifyMode.off || _pending.isEmpty) {
      if (mode == NotifyMode.off) {
        _pending.clear();
      }
      return;
    }

    final now = _clock();

    switch (mode) {
      case NotifyMode.off:
        _pending.clear();
        return;

      case NotifyMode.instant:
        final toNotify = List<NewMail>.from(_pending);
        _pending.clear();
        _lastFlushTime = now;

        if (toNotify.length > 3) {
          // Collapse into one summary notification.
          // slot(0) is the bundle slot.
          final title = UiStrings.notifySummaryTitle(toNotify.length);
          final senders = toNotify
              .map((m) => m.sender)
              .toSet()
              .toList();
          final body = UiStrings.notifyBundledBody(senders);
          await sink.show(
            DfNotificationIds.slot(0),
            title,
            body,
            payload: 'msg:bundle',
          );
        } else {
          // One notification per message (slots 1..20 ring)
          for (final msg in toNotify) {
            final slot = 1 + (_ringSlotIndex % 20);
            _ringSlotIndex++;
            await sink.show(
              DfNotificationIds.slot(slot),
              msg.sender,
              msg.subject,
              payload: 'msg:${msg.messageId}',
            );
          }
        }
        break;

      case NotifyMode.every5min:
      case NotifyMode.hourly:
        final interval = mode == NotifyMode.every5min
            ? const Duration(minutes: 5)
            : const Duration(hours: 1);

        if (_lastFlushTime != null && now.difference(_lastFlushTime!) < interval) {
          // Interval has not elapsed yet; keep pending in buffer.
          return;
        }

        final toNotify = List<NewMail>.from(_pending);
        _pending.clear();
        _lastFlushTime = now;

        final title = UiStrings.notifySummaryTitle(toNotify.length);
        final senders = toNotify
            .map((m) => m.sender)
            .toSet()
            .toList();
        final body = UiStrings.notifyBundledBody(senders);
        await sink.show(
          DfNotificationIds.slot(0),
          title,
          body,
          payload: 'msg:bundle',
        );
        break;
    }
  }
}

/// Riverpod provider exposing [NewMailNotifier].
///
/// Listens to [notifyModeProvider] so changes to mode update [NewMailNotifier.mode]
/// without disposing buffered messages.
final newMailNotifierProvider = Provider<NewMailNotifier>((ref) {
  final sink = ref.watch(notificationSinkProvider);
  final notifier = NewMailNotifier(
    sink: sink,
    mode: ref.read(notifyModeProvider),
  );
  ref.listen<NotifyMode>(notifyModeProvider, (_, next) {
    notifier.mode = next;
  });
  return notifier;
});

