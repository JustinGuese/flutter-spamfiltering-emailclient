import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:df_app_shell/df_app_shell.dart';
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

class AppNavShell extends ConsumerWidget {
  const AppNavShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
