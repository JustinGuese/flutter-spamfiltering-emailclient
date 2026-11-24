import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:df_app_shell/df_app_shell.dart';
import 'package:df_notifications/df_notifications.dart';
import '../../app/strings.dart';
import '../mailbox/mailbox_view.dart';
import '../reader/reader_view.dart';
import '../search/search_view.dart';
import '../settings/settings_view.dart';
import '../compose/compose_view.dart';
import 'folders_sidebar.dart';
import 'three_pane_layout.dart';
import '../../platform/platform_services.dart';

class NavIndexNotifier extends Notifier<int> {
  @override
  int build() => 0;
  void set(int val) => state = val;
}

final navIndexProvider = NotifierProvider<NavIndexNotifier, int>(NavIndexNotifier.new);

/// Routes a notification payload: if matching `msg:<id>`, switches to the Mail tab
/// (index 0) and selects the message with ID `<id>`. If `id` is empty or 'bundle',
/// clears the selected message so the mailbox list is shown.
void routeNotificationPayload(dynamic ref, String? payload) {
  if (payload == null || !payload.startsWith('msg:')) return;
  final msgId = payload.substring(4);
  ref.read(navIndexProvider.notifier).set(0);
  if (msgId.isNotEmpty && msgId != 'bundle') {
    ref.read(selectedMessageIdProvider.notifier).set(msgId);
  } else {
    ref.read(selectedMessageIdProvider.notifier).set(null);
  }
}

class AppNavShell extends ConsumerStatefulWidget {
  const AppNavShell({super.key});

  @override
  ConsumerState<AppNavShell> createState() => _AppNavShellState();
}

class _AppNavShellState extends ConsumerState<AppNavShell> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkNotificationTap();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkNotificationTap();
    }
  }

  void _checkNotificationTap() {
    final reminderService = ref.read(dfReminderServiceProvider);
    final payload = reminderService.consumePendingPayload();
    if (payload != null) {
      routeNotificationPayload(ref, payload);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentIndex = ref.watch(navIndexProvider);
    final selectedMsgId = ref.watch(selectedMessageIdProvider);
    final Widget foldersPane = FoldersSidebar(onCompose: () => _openCompose(context));

    Widget mailBody = ThreePaneLayout(
      foldersPane: foldersPane,
      listPane: MailboxView(
        onSelectMessage: (id) => ref.read(selectedMessageIdProvider.notifier).set(id),
        onCompose: () => _openCompose(context),
      ),
      readerPane: ReaderView(messageId: selectedMsgId),
      hasSelectedMessage: selectedMsgId != null,
      onBackToMailbox: () => ref.read(selectedMessageIdProvider.notifier).set(null),
    );

    Widget activeBody = switch (currentIndex) {
      0 => mailBody,
      1 => const SearchView(),
      2 => const SettingsView(),
      _ => mailBody,
    };

    return DfNavShell(
      currentIndex: currentIndex,
      onDestinationSelected: (idx) {
        // The reader pane is shared between tabs; start each tab on its list.
        ref.read(selectedMessageIdProvider.notifier).set(null);
        ref.read(navIndexProvider.notifier).set(idx);
      },
      destinations: const [
        DfNavDestination(
          icon: Icon(Icons.mail_outline),
          selectedIcon: Icon(Icons.mail),
          label: AppStrings.navMail,
        ),
        DfNavDestination(
          icon: Icon(Icons.search_outlined),
          selectedIcon: Icon(Icons.search),
          label: AppStrings.navSearch,
        ),
        DfNavDestination(
          icon: Icon(Icons.settings_outlined),
          selectedIcon: Icon(Icons.settings),
          label: AppStrings.navSettings,
        ),
      ],
      body: activeBody,
    );
  }

  void _openCompose(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ComposeView()),
    );
  }
}
