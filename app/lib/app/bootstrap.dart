import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:df_firebase_auth/df_firebase_auth.dart';
import 'package:df_funnel/df_funnel.dart';
import 'package:df_notifications/df_notifications.dart';
import '../community/blocklist_sync.dart';
import 'log.dart';
import '../mail/account_repository.dart';
import '../mail/sync_engine.dart';
import '../notifications/new_mail_notifier.dart';
import '../notifications/notify_prefs.dart';
import '../notifications/notify_types.dart';
import '../premium/filter_sync.dart';
import '../ui/shell/nav_shell.dart';

class SyncErrorNotifier extends Notifier<String?> {
  @override
  String? build() => null;
  void set(String? val) => state = val;
  void clear() => state = null;
}

final syncErrorProvider =
    NotifierProvider<SyncErrorNotifier, String?>(SyncErrorNotifier.new);

class AppBootstrap extends ConsumerStatefulWidget {
  final Widget child;
  final Future<bool> Function(BuildContext context, WidgetRef ref)?
      ensurePermission;

  const AppBootstrap({
    super.key,
    required this.child,
    this.ensurePermission,
  });

  @override
  ConsumerState<AppBootstrap> createState() => AppBootstrapState();
}

class AppBootstrapState extends ConsumerState<AppBootstrap>
    with WidgetsBindingObserver {
  Timer? _syncTimer;
  Timer? _flushTimer;
  bool _isCheckingSoftAsk = false;

  @visibleForTesting
  Timer? get syncTimer => _syncTimer;

  @visibleForTesting
  Timer? get flushTimer => _flushTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _runStartup();
    });
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    _flushTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkNotificationTap();
      _syncAll();
      _syncPremiumSlots();
      _flushNotifier();
      _checkSoftAsk();
    } else if (state == AppLifecycleState.paused) {
      _flushNotifier();
    }
  }

  void _runStartup() {
    // 0. Notification tap check on startup/cold launch
    _checkNotificationTap();

    // 1. Community blocklist sync & start 6h periodic sync
    final blocklistSync = ref.read(blocklistSyncProvider);
    blocklistSync.sync();
    blocklistSync.startPeriodicSync();

    // 2. Initial sync of all accounts
    _syncAll();

    // 3. Initial premium sync if entitled & signed in
    _syncPremiumSlots();

    // 4. Start periodic timers according to notify mode
    final mode = ref.read(notifyModeProvider);
    _resetTimers(mode);

    // 5. Offer notification soft-ask if first account added and mode != off
    _checkSoftAsk();
  }

  void _resetTimers(NotifyMode mode) {
    _syncTimer?.cancel();
    final syncInterval = mode == NotifyMode.instant
        ? const Duration(seconds: 60)
        : const Duration(minutes: 5);
    _syncTimer = Timer.periodic(syncInterval, (_) {
      _syncAll();
    });

    _flushTimer?.cancel();
    _flushTimer = null;
    if (mode == NotifyMode.every5min) {
      _flushTimer = Timer.periodic(const Duration(minutes: 5), (_) {
        _flushNotifier();
      });
    } else if (mode == NotifyMode.hourly) {
      _flushTimer = Timer.periodic(const Duration(hours: 1), (_) {
        _flushNotifier();
      });
    }
  }

  Future<void> _flushNotifier() async {
    try {
      await ref.read(newMailNotifierProvider).flush();
    } catch (e, st) {
      logError('flush notifications', e, st);
    }
  }

  void _checkNotificationTap() {
    try {
      final service = ref.read(dfReminderServiceProvider);
      final payload = service.consumePendingPayload();
      if (payload != null) {
        routeNotificationPayload(ref, payload);
      }
    } catch (e, st) {
      logError('checkNotificationTap', e, st);
    }
  }

  Future<void> _checkSoftAsk() async {
    if (_isCheckingSoftAsk) return;
    _isCheckingSoftAsk = true;
    try {
      if (!mounted) return;
      final accounts = ref.read(accountRepositoryProvider).listAccounts();
      if (accounts.isEmpty) return;
      final mode = ref.read(notifyModeProvider);
      if (mode == NotifyMode.off) return;
      final softAsked = ref.read(notifySoftAskedProvider);
      if (softAsked) return;

      ref.read(notifySoftAskedProvider.notifier).markOffered();

      if (!mounted) return;
      final requester =
          widget.ensurePermission ?? ensureDfNotificationPermission;
      final granted = await requester(context, ref);
      if (mounted) {
        ref.read(notificationBlockedProvider.notifier).setBlocked(!granted);
      }
    } catch (e, st) {
      logError('checkSoftAsk', e, st);
    } finally {
      _isCheckingSoftAsk = false;
    }
  }

  Future<void> _syncAll() async {
    final repo = ref.read(accountRepositoryProvider);
    final syncEngine = ref.read(syncEngineProvider);
    final accounts = repo.listAccounts();

    for (final acc in accounts) {
      try {
        await syncEngine.syncAccount(acc.id);
      } catch (e, st) {
        logError('sync ${acc.email}', e, st);
        ref.read(syncErrorProvider.notifier).set('Sync failed for ${acc.email}: $e');
      }
    }

    await _flushNotifier();
  }

  Future<void> _syncPremiumSlots() async {
    final isPro = ref.read(dfEffectivePremiumProvider);
    final user = ref.read(currentUserProvider);
    if (isPro && user != null) {
      try {
        await ref.read(filterSyncServiceProvider).syncAllSlots();
      } catch (e, st) {
        logError('premium filter sync', e, st);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(syncErrorProvider, (prev, next) {
      if (next != null) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text(next),
            duration: const Duration(seconds: 12),
            showCloseIcon: true,
          ),
        );
        ref.read(syncErrorProvider.notifier).clear();
      }
    });

    ref.listen<NotifyMode>(notifyModeProvider, (prev, next) {
      if (prev != next) {
        _resetTimers(next);
        _flushNotifier();
        if (next != NotifyMode.off) {
          _checkSoftAsk();
        }
      }
    });

    ref.listen(mailRevisionProvider, (prev, next) {
      _checkSoftAsk();
    });

    return widget.child;
  }
}
