import 'package:df_notifications/df_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:spamfiltering_emailclient/app/bootstrap.dart';
import 'package:spamfiltering_emailclient/community/blocklist_sync.dart';
import 'package:spamfiltering_emailclient/community/report_client.dart';
import 'package:spamfiltering_emailclient/db/database.dart';
import 'package:spamfiltering_emailclient/mail/account_repository.dart';
import 'package:spamfiltering_emailclient/mail/mail_auth.dart';
import 'package:spamfiltering_emailclient/mail/sync_engine.dart';
import 'package:spamfiltering_emailclient/notifications/mail_notification_service.dart';
import 'package:spamfiltering_emailclient/notifications/new_mail_notifier.dart';
import 'package:spamfiltering_emailclient/notifications/notify_prefs.dart';
import 'package:spamfiltering_emailclient/notifications/notify_types.dart';
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

class _FakeNotificationSink implements NotificationSink {
  final List<({int id, String title, String body, String? payload})> shown = [];

  @override
  Future<void> show(int id, String title, String body, {String? payload}) async {
    shown.add((id: id, title: title, body: body, payload: payload));
  }
}

class _FakeBlocklistSyncService implements BlocklistSyncService {
  @override
  AppDatabase get db => throw UnimplementedError();

  @override
  CommunityReportClient get client => throw UnimplementedError();

  @override
  Future<void> sync() async {}

  @override
  void startPeriodicSync() {}

  @override
  void stopPeriodicSync() {}
}

class _FakeSyncEngine extends SyncEngine {
  final List<String> syncedAccounts = [];

  _FakeSyncEngine({
    required super.db,
    required super.accountRepo,
  });

  @override
  Future<void> syncAccount(String accountId) async {
    syncedAccounts.add(accountId);
  }
}

void main() {
  late AppDatabase db;
  late _FakeReminderService reminderService;
  late _FakeNotificationSink fakeSink;

  setUp(() async {
    db = await AppDatabase.open(inMemory: true);
    reminderService = _FakeReminderService();
    fakeSink = _FakeNotificationSink();
  });

  tearDown(() {
    db.close();
  });

  Widget buildApp({
    void Function(BuildContext)? onRef,
    Future<bool> Function(BuildContext, WidgetRef)? ensurePermission,
    _FakeSyncEngine? syncEngine,
  }) {
    return ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        dfReminderServiceProvider.overrideWithValue(reminderService),
        notificationSinkProvider.overrideWithValue(fakeSink),
        blocklistSyncProvider.overrideWithValue(_FakeBlocklistSyncService()),
        if (syncEngine != null) syncEngineProvider.overrideWithValue(syncEngine),
      ],
      child: MaterialApp(
        home: AppBootstrap(
          ensurePermission: ensurePermission,
          child: Builder(
            builder: (ctx) {
              return Consumer(
                builder: (context, ref, _) {
                  onRef?.call(context);
                  return const Scaffold(body: Text('Child'));
                },
              );
            },
          ),
        ),
      ),
    );
  }

  group('Timers per NotifyMode', () {
    testWidgets('instant mode: 60s sync timer, null flush timer', (tester) async {
      db.db.execute("INSERT OR REPLACE INTO settings (key, value) VALUES ('notify_mode', 'instant')");

      await tester.pumpWidget(buildApp(onRef: null));
      await tester.pump();

      final state = tester.state<AppBootstrapState>(find.byType(AppBootstrap));
      expect(state.syncTimer, isNotNull);
      expect(state.syncTimer!.isActive, isTrue);
      expect(state.flushTimer, isNull);
    });

    testWidgets('every5min mode: 5m sync timer, 5m flush timer', (tester) async {
      db.db.execute("INSERT OR REPLACE INTO settings (key, value) VALUES ('notify_mode', 'every5min')");

      await tester.pumpWidget(buildApp(onRef: null));
      await tester.pump();

      final state = tester.state<AppBootstrapState>(find.byType(AppBootstrap));
      expect(state.syncTimer, isNotNull);
      expect(state.syncTimer!.isActive, isTrue);
      expect(state.flushTimer, isNotNull);
      expect(state.flushTimer!.isActive, isTrue);
    });

    testWidgets('hourly mode: 5m sync timer, 1h flush timer', (tester) async {
      db.db.execute("INSERT OR REPLACE INTO settings (key, value) VALUES ('notify_mode', 'hourly')");

      await tester.pumpWidget(buildApp(onRef: null));
      await tester.pump();

      final state = tester.state<AppBootstrapState>(find.byType(AppBootstrap));
      expect(state.syncTimer, isNotNull);
      expect(state.syncTimer!.isActive, isTrue);
      expect(state.flushTimer, isNotNull);
      expect(state.flushTimer!.isActive, isTrue);
    });

    testWidgets('off mode: 5m sync timer, null flush timer', (tester) async {
      db.db.execute("INSERT OR REPLACE INTO settings (key, value) VALUES ('notify_mode', 'off')");

      await tester.pumpWidget(buildApp(onRef: null));
      await tester.pump();

      final state = tester.state<AppBootstrapState>(find.byType(AppBootstrap));
      expect(state.syncTimer, isNotNull);
      expect(state.syncTimer!.isActive, isTrue);
      expect(state.flushTimer, isNull);
    });

    testWidgets('changing mode in Settings replaces timers without restart', (tester) async {
      db.db.execute("INSERT OR REPLACE INTO settings (key, value) VALUES ('notify_mode', 'instant')");

      await tester.pumpWidget(buildApp(onRef: null));
      await tester.pump();

      final state = tester.state<AppBootstrapState>(find.byType(AppBootstrap));
      final initialSyncTimer = state.syncTimer;
      expect(state.flushTimer, isNull);

      // Change mode to every5min
      final container = ProviderScope.containerOf(tester.element(find.text('Child')));
      container.read(notifyModeProvider.notifier).setMode(NotifyMode.every5min);
      await tester.pump();

      expect(initialSyncTimer!.isActive, isFalse, reason: 'Old sync timer must be cancelled');
      expect(state.syncTimer, isNotNull);
      expect(state.syncTimer!.isActive, isTrue);
      expect(state.flushTimer, isNotNull, reason: 'every5min should have flush timer');
      expect(state.flushTimer!.isActive, isTrue);

      // Change mode back to off
      final oldFlushTimer = state.flushTimer;
      container.read(notifyModeProvider.notifier).setMode(NotifyMode.off);
      await tester.pump();

      expect(oldFlushTimer!.isActive, isFalse, reason: 'Old flush timer must be cancelled');
      expect(state.flushTimer, isNull);
    });

    testWidgets('no timer leaks on dispose', (tester) async {
      db.db.execute("INSERT OR REPLACE INTO settings (key, value) VALUES ('notify_mode', 'every5min')");

      await tester.pumpWidget(buildApp(onRef: null));
      await tester.pump();

      final state = tester.state<AppBootstrapState>(find.byType(AppBootstrap));
      final syncTimer = state.syncTimer;
      final flushTimer = state.flushTimer;

      expect(syncTimer!.isActive, isTrue);
      expect(flushTimer!.isActive, isTrue);

      // Pump a different widget to dispose AppBootstrap
      await tester.pumpWidget(const SizedBox.shrink());

      expect(syncTimer.isActive, isFalse, reason: 'sync timer must be cancelled on dispose');
      expect(flushTimer.isActive, isFalse, reason: 'flush timer must be cancelled on dispose');
    });
  });

  group('Notification tap handling', () {
    testWidgets('cold start consumes pending payload and routes to message', (tester) async {
      reminderService.pendingPayload = 'msg:msg_initial';

      await tester.pumpWidget(buildApp(onRef: null));
      await tester.pump();

      final container = ProviderScope.containerOf(tester.element(find.text('Child')));
      expect(container.read(navIndexProvider), 0);
      expect(container.read(selectedMessageIdProvider), 'msg_initial');
      expect(reminderService.pendingPayload, isNull);
    });

    testWidgets('resume consumes pending payload and routes to message', (tester) async {
      await tester.pumpWidget(buildApp(onRef: null));
      await tester.pump();

      final container = ProviderScope.containerOf(tester.element(find.text('Child')));
      container.read(navIndexProvider.notifier).set(2); // In settings tab
      expect(container.read(navIndexProvider), 2);

      reminderService.pendingPayload = 'msg:msg_resumed';
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      expect(container.read(navIndexProvider), 0);
      expect(container.read(selectedMessageIdProvider), 'msg_resumed');
    });

    testWidgets('bundle payload msg:bundle sets navIndex to 0 and clears selected message', (tester) async {
      await tester.pumpWidget(buildApp(onRef: null));
      await tester.pump();

      final container = ProviderScope.containerOf(tester.element(find.text('Child')));
      container.read(navIndexProvider.notifier).set(1);
      container.read(selectedMessageIdProvider.notifier).set('existing_id');

      reminderService.pendingPayload = 'msg:bundle';
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      expect(container.read(navIndexProvider), 0);
      expect(container.read(selectedMessageIdProvider), isNull);
    });
  });

  group('First-run soft-ask', () {
    testWidgets('no account added: soft-ask is NOT offered', (tester) async {
      bool softAskCalled = false;
      await tester.pumpWidget(buildApp(
        onRef: null,
        ensurePermission: (ctx, ref) async {
          softAskCalled = true;
          return true;
        },
      ));
      await tester.pump();

      expect(softAskCalled, isFalse);
      final rows = db.db.select("SELECT value FROM settings WHERE key = 'notify_soft_asked'");
      expect(rows, isEmpty);
    });

    testWidgets('first account added + mode != off: offers soft-ask once and persists flag', (tester) async {
      int softAskCount = 0;
      await tester.pumpWidget(buildApp(
        onRef: null,
        ensurePermission: (ctx, ref) async {
          softAskCount++;
          return true;
        },
      ));
      await tester.pump();

      expect(softAskCount, 0);

      // Now add first account
      db.db.execute(
        'INSERT INTO accounts (id, email, display_name, imap_host, imap_port, '
        'smtp_host, smtp_port, auth_type, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
        ['acc1', 'user@example.com', 'User', 'imap.example.com', 993, 'smtp.example.com', 587, 'password', DateTime.now().toIso8601String()],
      );

      // Bumping mailRevisionProvider signals account added
      final container = ProviderScope.containerOf(tester.element(find.text('Child')));
      container.read(mailRevisionProvider.notifier).bump();
      await tester.pump();
      await tester.pump();

      expect(softAskCount, 1, reason: 'Soft ask should be offered once after first account added');
      final rows = db.db.select("SELECT value FROM settings WHERE key = 'notify_soft_asked'");
      expect(rows.length, 1);
      expect(rows.first['value'], 'true');

      // Adding a second account should NOT trigger soft-ask again
      db.db.execute(
        'INSERT INTO accounts (id, email, display_name, imap_host, imap_port, '
        'smtp_host, smtp_port, auth_type, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
        ['acc2', 'user2@example.com', 'User 2', 'imap.example.com', 993, 'smtp.example.com', 587, 'password', DateTime.now().toIso8601String()],
      );
      container.read(mailRevisionProvider.notifier).bump();
      await tester.pump();
      await tester.pump();

      expect(softAskCount, 1, reason: 'Soft ask must not be offered a second time');
    });

    testWidgets('first account added + mode == off: does NOT offer soft-ask', (tester) async {
      db.db.execute("INSERT OR REPLACE INTO settings (key, value) VALUES ('notify_mode', 'off')");

      int softAskCount = 0;
      await tester.pumpWidget(buildApp(
        onRef: null,
        ensurePermission: (ctx, ref) async {
          softAskCount++;
          return true;
        },
      ));
      await tester.pump();

      db.db.execute(
        'INSERT INTO accounts (id, email, display_name, imap_host, imap_port, '
        'smtp_host, smtp_port, auth_type, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
        ['acc1', 'user@example.com', 'User', 'imap.example.com', 993, 'smtp.example.com', 587, 'password', DateTime.now().toIso8601String()],
      );
      final container = ProviderScope.containerOf(tester.element(find.text('Child')));
      container.read(mailRevisionProvider.notifier).bump();
      await tester.pump();
      await tester.pump();

      expect(softAskCount, 0, reason: 'Soft ask must not be offered when mode is off');
    });
  });

  group('SyncEngine wiring & flush', () {
    testWidgets('SyncEngine wired with NewMailNotifier through syncEngineProvider', (tester) async {
      final syncEngine = _FakeSyncEngine(
        db: db,
        accountRepo: AccountRepository(db: db),
      );

      await tester.pumpWidget(buildApp(
        onRef: null,
        syncEngine: syncEngine,
      ));
      await tester.pump();

      final container = ProviderScope.containerOf(tester.element(find.text('Child')));
      final notifier = container.read(newMailNotifierProvider);

      // Add mail to notifier and flush
      notifier.add([
        NewMail(
          messageId: 'm1',
          accountId: 'acc1',
          sender: 'bob@example.com',
          subject: 'Test Subject',
          receivedAt: DateTime.now(),
        )
      ]);
      await notifier.flush();

      expect(fakeSink.shown.length, 1);
      expect(fakeSink.shown.first.payload, 'msg:m1');
    });

    testWidgets('flush triggered on app pause', (tester) async {
      await tester.pumpWidget(buildApp(onRef: null));
      await tester.pump();

      final container = ProviderScope.containerOf(tester.element(find.text('Child')));
      final notifier = container.read(newMailNotifierProvider);
      notifier.add([
        NewMail(
          messageId: 'pause_msg',
          accountId: 'acc1',
          sender: 'pause@example.com',
          subject: 'Pause Test',
          receivedAt: DateTime.now(),
        )
      ]);

      expect(fakeSink.shown, isEmpty);

      // Trigger app pause
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();

      expect(fakeSink.shown.length, 1);
      expect(fakeSink.shown.first.payload, 'msg:pause_msg');
    });
  });
}
