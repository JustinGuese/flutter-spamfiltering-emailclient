// ignore_for_file: depend_on_referenced_packages
import 'package:df_notifications/df_notifications.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spamfiltering_emailclient/notifications/mail_notification_service.dart';
import 'package:spamfiltering_emailclient/notifications/notify_types.dart';

class _FakeReminderService extends DfReminderService {
  _FakeReminderService() : super.base();

  bool initCalled = false;
  bool requestPermissionCalled = false;
  final List<DfReminder> scheduled = [];
  final List<int> cancelled = [];
  String? nextPayload;
  final List<_ShowCall> shown = [];

  @override
  Future<void> init() async {
    initCalled = true;
  }

  @override
  Future<bool> requestPermission() async {
    requestPermissionCalled = true;
    return true;
  }

  @override
  Future<void> schedule(DfReminder reminder) async {
    scheduled.add(reminder);
  }

  @override
  Future<void> cancel(int id) async {
    cancelled.add(id);
  }

  @override
  Future<void> cancelMany(Iterable<int> ids) async {
    cancelled.addAll(ids);
  }

  @override
  String? consumePendingPayload() {
    final p = nextPayload;
    nextPayload = null;
    return p;
  }

  @override
  Future<void> show(
    int id,
    String title,
    String body, {
    DfNotificationChannel channel = DfNotificationChannel.defaultChannel,
    String? payload,
  }) async {
    shown.add(_ShowCall(id, title, body, channel, payload));
  }
}

class _ShowCall {
  final int id;
  final String title;
  final String body;
  final DfNotificationChannel channel;
  final String? payload;

  _ShowCall(this.id, this.title, this.body, this.channel, this.payload);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  final List<MethodCall> calls = [];

  setUp(() {
    calls.clear();
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      calls.add(call);
      switch (call.method) {
        case 'initialize':
          return true;
        case 'getNotificationAppLaunchDetails':
          return <dynamic, dynamic>{
            'notificationLaunchedApp': false,
            'notificationResponse': null,
          };
        case 'requestNotificationsPermission':
        case 'requestPermissions':
          return true;
        case 'show':
        case 'zonedSchedule':
        case 'cancel':
        case 'cancelAll':
          return null;
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('MailNotificationService', () {
    test('show delegates to reminderService with kMailNotificationChannel', () async {
      final fake = _FakeReminderService();
      final service = MailNotificationService(reminderService: fake);

      await service.show(
        DfNotificationIds.slot(0),
        '3 new messages',
        'Alice, Bob, Carol',
        payload: 'msg:bundle',
      );

      expect(fake.shown.length, 1);
      final call = fake.shown.first;
      expect(call.id, DfNotificationIds.slot(0));
      expect(call.title, '3 new messages');
      expect(call.body, 'Alice, Bob, Carol');
      expect(call.channel.id, 'mail_new');
      expect(call.channel.name, 'New mail');
      expect(call.payload, 'msg:bundle');
    });

    test('show per-message rings with custom channel', () async {
      final fake = _FakeReminderService();
      final service = MailNotificationService(reminderService: fake);

      await service.show(
        DfNotificationIds.slot(1),
        'Important',
        'Invoice attached',
        payload: 'msg:msg_123',
      );

      expect(fake.shown.length, 1);
      expect(fake.shown.first.id, DfNotificationIds.slot(1));
      expect(fake.shown.first.payload, 'msg:msg_123');
    });

    test('delegates init, requestPermission, cancel, consumePendingPayload', () async {
      final fake = _FakeReminderService();
      fake.nextPayload = 'msg:cold_start';
      final service = MailNotificationService(reminderService: fake);

      await service.init();
      expect(fake.initCalled, isTrue);

      final granted = await service.requestPermission();
      expect(granted, isTrue);
      expect(fake.requestPermissionCalled, isTrue);

      expect(service.consumePendingPayload(), 'msg:cold_start');
      expect(service.consumePendingPayload(), isNull);

      await service.cancel(42);
      expect(fake.cancelled, contains(42));

      await service.cancelMany([101, 102]);
      expect(fake.cancelled, containsAll([101, 102]));
    });

    test('Provider wiring provides MailNotificationService and NotificationSink', () {
      final fake = _FakeReminderService();
      final container = ProviderContainer(
        overrides: [
          dfReminderServiceProvider.overrideWithValue(fake),
        ],
      );
      addTearDown(container.dispose);

      final mailService = container.read(mailNotificationServiceProvider);
      final sink = container.read(notificationSinkProvider);

      expect(mailService, isA<MailNotificationService>());
      expect(sink, isA<NotificationSink>());
      expect(identical(mailService, sink), isTrue);
    });

    test('DfNotificationConfig override produces valid Windows and channel config', () {
      const config = DfNotificationConfig(
        windowsAppName: 'DataFortress Mail',
        windowsAppUserModelId: 'DataFortress.Mail',
        windowsGuid: 'f87a8b60-7058-47bc-9df2-501b44ecdcbb',
        defaultChannel: kMailNotificationChannel,
      );

      expect(config.windowsAppName, 'DataFortress Mail');
      expect(config.windowsAppUserModelId, 'DataFortress.Mail');
      expect(config.windowsGuid, 'f87a8b60-7058-47bc-9df2-501b44ecdcbb');
      expect(config.defaultChannel.id, 'mail_new');
    });

    test('native/default service init does not throw', () async {
      final service = MailNotificationService();
      await expectLater(service.init(), completes);
      expect(calls.where((c) => c.method == 'initialize'), isNotEmpty);
    });
  });
}
