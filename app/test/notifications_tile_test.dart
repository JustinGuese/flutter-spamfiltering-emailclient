import 'package:df_notifications/df_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:spamfiltering_emailclient/app/ui_strings.dart';
import 'package:spamfiltering_emailclient/db/database.dart';
import 'package:spamfiltering_emailclient/notifications/mail_notification_service.dart';
import 'package:spamfiltering_emailclient/notifications/notify_prefs.dart';
import 'package:spamfiltering_emailclient/notifications/notify_types.dart';
import 'package:spamfiltering_emailclient/ui/settings/notifications_tile.dart';

class _FakeNotificationSink implements NotificationSink {
  final List<({int id, String title, String body, String? payload})> shown = [];

  @override
  Future<void> show(int id, String title, String body, {String? payload}) async {
    shown.add((id: id, title: title, body: body, payload: payload));
  }
}

void main() {
  late AppDatabase db;
  late _FakeNotificationSink fakeSink;

  setUp(() async {
    db = await AppDatabase.open(inMemory: true);
    fakeSink = _FakeNotificationSink();
  });

  tearDown(() {
    db.close();
  });

  Widget createWidget({
    Future<bool> Function(BuildContext, WidgetRef)? ensurePermission,
  }) {
    return ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        notificationSinkProvider.overrideWithValue(fakeSink),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: NotificationsTile(
              ensurePermission: ensurePermission,
            ),
          ),
        ),
      ),
    );
  }

  group('notifyModeProvider', () {
    test('defaults to NotifyMode.instant when settings table is empty', () {
      final container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
      addTearDown(container.dispose);

      expect(container.read(notifyModeProvider), NotifyMode.instant);
    });

    test('persists mode to SQLite settings table and restores on rebuild', () {
      final container1 = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
      container1.read(notifyModeProvider.notifier).setMode(NotifyMode.every5min);
      expect(container1.read(notifyModeProvider), NotifyMode.every5min);
      container1.dispose();

      final rows = db.db.select("SELECT value FROM settings WHERE key = 'notify_mode'");
      expect(rows.length, 1);
      expect(rows.first['value'], 'every5min');

      final container2 = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
      addTearDown(container2.dispose);
      expect(container2.read(notifyModeProvider), NotifyMode.every5min);
    });

    test('notificationBlockedProvider persists and restores', () {
      final container1 = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
      expect(container1.read(notificationBlockedProvider), false);
      container1.read(notificationBlockedProvider.notifier).setBlocked(true);
      expect(container1.read(notificationBlockedProvider), true);
      container1.dispose();

      final rows = db.db.select(
        "SELECT value FROM settings WHERE key = 'notify_permission_blocked'",
      );
      expect(rows.first['value'], 'true');

      final container2 = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
      addTearDown(container2.dispose);
      expect(container2.read(notificationBlockedProvider), true);
    });
  });

  group('NotificationsTile UI', () {
    testWidgets('renders choice tile and send test notification tile', (tester) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      expect(find.text(UiStrings.notifyModeTitle), findsOneWidget);
      expect(find.text(UiStrings.notifyModeInstant), findsOneWidget);
      expect(find.text(UiStrings.notifySendTest), findsOneWidget);
    });

    testWidgets('shows blocked warning when permission is denied', (tester) async {
      db.db.execute('''
        INSERT OR REPLACE INTO settings (key, value)
        VALUES ('notify_permission_blocked', 'true')
      ''');

      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      expect(find.text(UiStrings.notifyBlockedSubtitle), findsOneWidget);
    });

    testWidgets('does not show blocked warning when mode is Off even if flag was true', (tester) async {
      db.db.execute('''
        INSERT OR REPLACE INTO settings (key, value)
        VALUES ('notify_mode', 'off'), ('notify_permission_blocked', 'true')
      ''');

      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      expect(find.text(UiStrings.notifyBlockedSubtitle), findsNothing);
      expect(find.text(UiStrings.notifyModeOff), findsOneWidget);
    });

    testWidgets('choosing a non-off mode requests permission and updates blocked status if denied', (tester) async {
      var permissionRequested = false;

      await tester.pumpWidget(createWidget(
        ensurePermission: (context, ref) async {
          permissionRequested = true;
          return false; // Denied
        },
      ));
      await tester.pumpAndSettle();

      // Open bottom sheet
      await tester.tap(find.text(UiStrings.notifyModeTitle));
      await tester.pumpAndSettle();

      // Options in sheet
      expect(find.text(UiStrings.notifyModeOff), findsOneWidget);
      expect(find.text(UiStrings.notifyModeEvery5min), findsOneWidget);
      expect(find.text(UiStrings.notifyModeHourly), findsOneWidget);

      // Select 'Hourly summary'
      await tester.tap(find.text(UiStrings.notifyModeHourly));
      await tester.pumpAndSettle();

      expect(permissionRequested, isTrue);
      expect(find.text(UiStrings.notifyBlockedSubtitle), findsOneWidget);

      // Mode is kept in SQLite
      final rows = db.db.select("SELECT value FROM settings WHERE key = 'notify_mode'");
      expect(rows.first['value'], 'hourly');
    });

    testWidgets('choosing a non-off mode clears blocked status if granted', (tester) async {
      db.db.execute('''
        INSERT OR REPLACE INTO settings (key, value)
        VALUES ('notify_permission_blocked', 'true')
      ''');

      await tester.pumpWidget(createWidget(
        ensurePermission: (context, ref) async => true, // Granted
      ));
      await tester.pumpAndSettle();

      expect(find.text(UiStrings.notifyBlockedSubtitle), findsOneWidget);

      // Open bottom sheet
      await tester.tap(find.text(UiStrings.notifyModeTitle));
      await tester.pumpAndSettle();

      // Select 'Bundled every 5 minutes'
      await tester.tap(find.text(UiStrings.notifyModeEvery5min));
      await tester.pumpAndSettle();

      expect(find.text(UiStrings.notifyBlockedSubtitle), findsNothing);
      expect(find.text(UiStrings.notifyModeEvery5min), findsOneWidget);
    });

    testWidgets('choosing Off clears blocked flag without requesting permission', (tester) async {
      var permissionRequested = false;
      db.db.execute('''
        INSERT OR REPLACE INTO settings (key, value)
        VALUES ('notify_permission_blocked', 'true')
      ''');

      await tester.pumpWidget(createWidget(
        ensurePermission: (context, ref) async {
          permissionRequested = true;
          return true;
        },
      ));
      await tester.pumpAndSettle();

      // Open bottom sheet
      await tester.tap(find.text(UiStrings.notifyModeTitle));
      await tester.pumpAndSettle();

      // Select 'Off'
      await tester.tap(find.text(UiStrings.notifyModeOff));
      await tester.pumpAndSettle();

      expect(permissionRequested, isFalse);
      expect(find.text(UiStrings.notifyBlockedSubtitle), findsNothing);
      expect(find.text(UiStrings.notifyModeOff), findsOneWidget);
    });

    testWidgets('tapping Send test notification triggers sink.show', (tester) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text(UiStrings.notifySendTest));
      await tester.pumpAndSettle();

      expect(fakeSink.shown.length, 1);
      final notif = fakeSink.shown.first;
      expect(notif.id, DfNotificationIds.slot(0));
      expect(notif.title, UiStrings.notifyTestTitle);
      expect(notif.body, UiStrings.notifyTestBody);
    });
  });
}
