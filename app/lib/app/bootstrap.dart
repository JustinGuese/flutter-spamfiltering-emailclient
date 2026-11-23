import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:df_funnel/df_funnel.dart';
import 'package:df_firebase_auth/df_firebase_auth.dart';
import '../community/blocklist_sync.dart';
import 'log.dart';
import '../mail/account_repository.dart';
import '../mail/sync_engine.dart';
import '../premium/filter_sync.dart';

class SyncErrorNotifier extends Notifier<String?> {
  @override
  String? build() => null;
  void set(String? val) => state = val;
  void clear() => state = null;
}

final syncErrorProvider = NotifierProvider<SyncErrorNotifier, String?>(SyncErrorNotifier.new);

class AppBootstrap extends ConsumerStatefulWidget {
  final Widget child;

  const AppBootstrap({super.key, required this.child});

  @override
  ConsumerState<AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends ConsumerState<AppBootstrap> with WidgetsBindingObserver {
  Timer? _fiveMinTimer;

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
    _fiveMinTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncAll();
      _syncPremiumSlots();
    }
  }

  void _runStartup() {
    // 1. Community blocklist sync & start 6h periodic sync
    final blocklistSync = ref.read(blocklistSyncProvider);
    blocklistSync.sync();
    blocklistSync.startPeriodicSync();

    // 2. Initial sync of all accounts
    _syncAll();

    // 3. Initial premium sync if entitled & signed in
    _syncPremiumSlots();

    // 4. Periodic 5-minute timer for account sync
    _fiveMinTimer?.cancel();
    _fiveMinTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      _syncAll();
    });
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

    return widget.child;
  }
}
