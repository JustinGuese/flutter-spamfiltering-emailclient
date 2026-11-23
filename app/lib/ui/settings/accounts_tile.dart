import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:df_theme/df_theme.dart';
import '../../app/log.dart';
import '../../app/strings.dart';
import '../../app/ui_strings.dart';
import '../../mail/sync_engine.dart';
import '../../platform/platform_services.dart';
import '../../mail/account_repository.dart';
import '../account_setup/account_setup_view.dart';

class AccountsTile extends ConsumerWidget {
  const AccountsTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.df.colors;
    ref.watch(mailRevisionProvider); // add/remove/sync all bump this
    final accountRepo = ref.watch(accountRepositoryProvider);
    final accounts = accountRepo.listAccounts();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border(bottom: BorderSide(color: palette.hairline)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                AppStrings.settingsAccounts,
                style: TextStyle(
                  fontFamily: 'Public Sans',
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: palette.textPrimary,
                ),
              ),
              TextButton.icon(
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add Account', style: TextStyle(fontSize: 12)),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AccountSetupView()),
                  );
                },
              ),
            ],
          ),
          if (accounts.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No accounts configured.',
                style: TextStyle(
                  fontFamily: 'Public Sans',
                  fontSize: 12,
                  color: palette.textTertiary,
                ),
              ),
            )
          else
            for (final acc in accounts)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.account_circle_outlined),
                title: Text(acc.displayName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                subtitle: Text(acc.email, style: const TextStyle(fontFamily: 'JetBrains Mono', fontSize: 11)),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  onPressed: () => _confirmRemove(context, ref, acc),
                ),
              ),
        ],
      ),
    );
  }

  Future<void> _confirmRemove(BuildContext context, WidgetRef ref, AccountRecord acc) async {
    final repo = ref.read(accountRepositoryProvider);
    final revision = ref.read(mailRevisionProvider.notifier);
    final folder = ref.read(selectedFolderIdProvider.notifier);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(UiStrings.removeAccountTitle),
        content: Text('${acc.email}\n\n${UiStrings.removeAccountBody}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text(UiStrings.removeAccountCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(UiStrings.removeAccountConfirm),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      // Local rows are removed synchronously inside; only the keychain cleanup
      // can be slow, so it must not keep the UI waiting.
      await repo.deleteAccount(acc.id).timeout(const Duration(seconds: 5));
    } catch (e, st) {
      logError('remove account ${acc.email}', e, st);
    }
    folder.set(null); // the selected folder may have belonged to this account
    revision.bump();
  }
}
