import 'package:df_notifications/df_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spamfiltering_emailclient/notifications/new_mail_notifier.dart';
import 'package:spamfiltering_emailclient/notifications/notify_types.dart';

class _RecordedNotification {
  final int id;
  final String title;
  final String body;
  final String? payload;

  _RecordedNotification(this.id, this.title, this.body, this.payload);
}

class _FakeNotificationSink implements NotificationSink {
  final List<_RecordedNotification> shown = [];

  @override
  Future<void> show(int id, String title, String body, {String? payload}) async {
    shown.add(_RecordedNotification(id, title, body, payload));
  }

  void clear() => shown.clear();
}

NewMail _mail(String id, {String sender = 'alice@example.com', String subject = 'Hello'}) {
  return NewMail(
    messageId: id,
    accountId: 'acc1',
    sender: sender,
    subject: subject,
    receivedAt: DateTime(2026, 11, 24, 10, 0),
  );
}

void main() {
  late _FakeNotificationSink sink;
  late DateTime currentTime;

  setUp(() {
    sink = _FakeNotificationSink();
    currentTime = DateTime(2026, 11, 24, 12, 0, 0);
  });

  group('NewMailNotifier', () {
    test('nothing pending -> nothing shown across all modes', () async {
      for (final mode in NotifyMode.values) {
        final notifier = NewMailNotifier(
          sink: sink,
          clock: () => currentTime,
          mode: mode,
        );
        await notifier.flush();
        expect(sink.shown, isEmpty, reason: 'mode $mode with empty buffer should show nothing');
      }
    });

    test('mode off drops everything immediately and on flush', () async {
      final notifier = NewMailNotifier(
        sink: sink,
        clock: () => currentTime,
        mode: NotifyMode.off,
      );

      notifier.add([_mail('m1')]);
      expect(notifier.pending, isEmpty);

      await notifier.flush();
      expect(sink.shown, isEmpty);
    });

    test('mode instant: 1 to 3 messages show individual notifications with sender and subject', () async {
      final notifier = NewMailNotifier(
        sink: sink,
        clock: () => currentTime,
        mode: NotifyMode.instant,
      );

      notifier.add([
        _mail('m1', sender: 'alice@example.com', subject: 'Report 1'),
        _mail('m2', sender: 'bob@example.com', subject: 'Report 2'),
        _mail('m3', sender: 'carol@example.com', subject: 'Report 3'),
      ]);

      await notifier.flush();

      expect(sink.shown.length, 3);
      expect(sink.shown[0].id, DfNotificationIds.slot(1));
      expect(sink.shown[0].title, 'alice@example.com');
      expect(sink.shown[0].body, 'Report 1');
      expect(sink.shown[0].payload, 'msg:m1');

      expect(sink.shown[1].id, DfNotificationIds.slot(2));
      expect(sink.shown[1].title, 'bob@example.com');
      expect(sink.shown[1].body, 'Report 2');
      expect(sink.shown[1].payload, 'msg:m2');

      expect(sink.shown[2].id, DfNotificationIds.slot(3));
      expect(sink.shown[2].title, 'carol@example.com');
      expect(sink.shown[2].body, 'Report 3');
      expect(sink.shown[2].payload, 'msg:m3');

      expect(notifier.pending, isEmpty);
    });

    test('mode instant: more than 3 messages within a flush collapse into summary', () async {
      final notifier = NewMailNotifier(
        sink: sink,
        clock: () => currentTime,
        mode: NotifyMode.instant,
      );

      notifier.add([
        _mail('m1', sender: 'alice@example.com', subject: 'One'),
        _mail('m2', sender: 'bob@example.com', subject: 'Two'),
        _mail('m3', sender: 'carol@example.com', subject: 'Three'),
        _mail('m4', sender: 'dave@example.com', subject: 'Four'),
      ]);

      await notifier.flush();

      expect(sink.shown.length, 1);
      final notification = sink.shown.first;
      expect(notification.id, DfNotificationIds.slot(0)); // Bundle slot
      expect(notification.title, '4 new messages');
      expect(notification.body, 'alice@example.com, bob@example.com, carol@example.com, dave@example.com');
      expect(notification.payload, 'msg:bundle');
      expect(notifier.pending, isEmpty);
    });

    test('mode every5min: nothing shown until 5 minutes elapse since last flush, then one bundled notification', () async {
      final notifier = NewMailNotifier(
        sink: sink,
        clock: () => currentTime,
        mode: NotifyMode.every5min,
      );

      notifier.add([
        _mail('m1', sender: 'alice@example.com', subject: 'One'),
        _mail('m2', sender: 'bob@example.com', subject: 'Two'),
      ]);

      // First flush triggers bundling and records lastFlushTime
      await notifier.flush();
      expect(sink.shown.length, 1);
      expect(sink.shown.first.id, DfNotificationIds.slot(0));
      expect(sink.shown.first.title, '2 new messages');
      expect(sink.shown.first.body, 'alice@example.com, bob@example.com');
      sink.clear();

      // Add another message after 3 minutes (less than 5 minutes)
      currentTime = currentTime.add(const Duration(minutes: 3));
      notifier.add([_mail('m3', sender: 'carol@example.com', subject: 'Three')]);
      await notifier.flush();

      expect(sink.shown, isEmpty, reason: 'Interval has not elapsed yet');
      expect(notifier.pending.length, 1);

      // Advance clock past 5 minutes (e.g. 5m 1s total)
      currentTime = currentTime.add(const Duration(minutes: 2, seconds: 1));
      await notifier.flush();

      expect(sink.shown.length, 1);
      expect(sink.shown.first.id, DfNotificationIds.slot(0));
      expect(sink.shown.first.title, '1 new messages');
      expect(sink.shown.first.body, 'carol@example.com');
      expect(notifier.pending, isEmpty);
    });

    test('mode hourly: nothing shown until 1 hour elapses since last flush, then one bundled notification', () async {
      final notifier = NewMailNotifier(
        sink: sink,
        clock: () => currentTime,
        mode: NotifyMode.hourly,
      );

      notifier.add([_mail('m1', sender: 'alice@example.com', subject: 'One')]);

      // First flush shows notification
      await notifier.flush();
      expect(sink.shown.length, 1);
      expect(sink.shown.first.title, '1 new messages');
      sink.clear();

      // Add another message 30 minutes later
      currentTime = currentTime.add(const Duration(minutes: 30));
      notifier.add([_mail('m2', sender: 'bob@example.com', subject: 'Two')]);
      await notifier.flush();

      expect(sink.shown, isEmpty);
      expect(notifier.pending.length, 1);

      // Advance clock past 1 hour from last flush (total 60 mins 1 sec)
      currentTime = currentTime.add(const Duration(minutes: 30, seconds: 1));
      await notifier.flush();

      expect(sink.shown.length, 1);
      expect(sink.shown.first.title, '1 new messages');
      expect(sink.shown.first.body, 'bob@example.com');
      expect(notifier.pending, isEmpty);
    });
  });
}
