import 'package:df_notifications/df_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:spamfiltering_emailclient/db/database.dart';
import 'package:spamfiltering_emailclient/platform/platform_services.dart';
import 'package:spamfiltering_emailclient/ui/shell/nav_shell.dart';

class _FakeReminderService implements DfReminderService {
  String? pendingPayload;

  @override
  String? consumePendingPayload() {
    final p = pendingPayload;
    pendingPayload = null;
    return p;
  }

  @override
  Future<void> cancel(int id) async {}

  @override
  Future<void> cancelMany(Iterable<int> ids) async {}

  @override
  Future<void> init({DfNotificationConfig? config}) async {}

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> schedule(DfReminder reminder) async {}

  @override
  Future<void> show(
    int id,
    String title,
    String body, {
    DfNotificationChannel channel = const DfNotificationChannel(id: 'default', name: 'default'),
    String? payload,
  }) async {}
}

void main() {
  group('routeNotificationPayload', () {
    test('routes msg:<id> by setting navIndex to 0 and selecting message', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(navIndexProvider.notifier).set(2);
      expect(container.read(navIndexProvider), 2);
      expect(container.read(selectedMessageIdProvider), isNull);

      routeNotificationPayload(container as dynamic, 'msg:message_456');

      expect(container.read(navIndexProvider), 0);
      expect(container.read(selectedMessageIdProvider), 'message_456');
    });

    test('routes msg:bundle by setting navIndex to 0 and clearing selected message', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(navIndexProvider.notifier).set(1);
      container.read(selectedMessageIdProvider.notifier).set('existing_message');

      routeNotificationPayload(container as dynamic, 'msg:bundle');

      expect(container.read(navIndexProvider), 0);
      expect(container.read(selectedMessageIdProvider), isNull);
    });

    test('ignores non-msg payloads and null', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(navIndexProvider.notifier).set(2);
      container.read(selectedMessageIdProvider.notifier).set('msg_x');

      routeNotificationPayload(container as dynamic, 'test');
      routeNotificationPayload(container as dynamic, null);
      routeNotificationPayload(container as dynamic, 'other:123');

      expect(container.read(navIndexProvider), 2);
      expect(container.read(selectedMessageIdProvider), 'msg_x');
    });
  });

  group('AppNavShell tap routing lifecycle', () {
    late AppDatabase db;
    late _FakeReminderService reminderService;

    setUp(() async {
      db = await AppDatabase.open(inMemory: true);
      reminderService = _FakeReminderService();
    });

    tearDown(() {
      db.close();
    });

    testWidgets('consumes pending payload on mount and selects message', (tester) async {
      reminderService.pendingPayload = 'msg:mount_target';

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            dfReminderServiceProvider.overrideWithValue(reminderService),
          ],
          child: const MaterialApp(
            home: AppNavShell(),
          ),
        ),
      );
      await tester.pump();

      final container = ProviderScope.containerOf(tester.element(find.byType(AppNavShell)));
      expect(container.read(navIndexProvider), 0);
      expect(container.read(selectedMessageIdProvider), 'mount_target');
      expect(reminderService.pendingPayload, isNull);
    });

    testWidgets('consumes pending payload on resume', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            dfReminderServiceProvider.overrideWithValue(reminderService),
          ],
          child: const MaterialApp(
            home: AppNavShell(),
          ),
        ),
      );
      await tester.pump();

      final container = ProviderScope.containerOf(tester.element(find.byType(AppNavShell)));
      container.read(navIndexProvider.notifier).set(2);
      expect(container.read(navIndexProvider), 2);

      reminderService.pendingPayload = 'msg:resume_target';
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      expect(container.read(navIndexProvider), 0);
      expect(container.read(selectedMessageIdProvider), 'resume_target');
      expect(reminderService.pendingPayload, isNull);
    });
  });
}
