import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:df_theme/df_theme.dart';
import '../../app/bootstrap.dart';
import '../../app/log.dart';
import '../../app/strings.dart';
import '../../app/ui_strings.dart';
import '../../mail/mail_auth.dart';
import '../../mail/oauth/oauth_flow.dart';
import '../../mail/sync_engine.dart';
import '../../platform/platform_services.dart';
import '../../mail/account_repository.dart';
import '../account_setup/account_setup_view.dart';

class AccountsTile extends ConsumerStatefulWidget {
  const AccountsTile({super.key});

  @override
  ConsumerState<AccountsTile> createState() => _AccountsTileState();
}

class _AccountsTileState extends ConsumerState<AccountsTile> {
  final Set<String> _reconnectingAccountIds = {};

  @override
  Widget build(BuildContext context) {
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
            for (final acc in accounts) ...[
              _buildAccountTile(context, palette, accountRepo, acc),
            ],
        ],
      ),
    );
  }

  Widget _buildAccountTile(
    BuildContext context,
    DfPalette palette,
    AccountRepository accountRepo,
    AccountRecord acc,
  ) {
    final isOAuth = acc.authType == 'oauth_google' || acc.authType == 'oauth_microsoft';
    final needsReauth = isOAuth && accountRepo.isReauthRequired(acc.id);
    final isReconnecting = _reconnectingAccountIds.contains(acc.id);

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.account_circle_outlined),
      title: Text(
        acc.displayName,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            acc.email,
            style: const TextStyle(fontFamily: 'JetBrains Mono', fontSize: 11),
          ),
          if (needsReauth) ...[
            const SizedBox(height: 2),
            Text(
              UiStrings.accountNeedsReauth,
              style: TextStyle(
                fontSize: 11,
                color: palette.warning.base,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (needsReauth) ...[
            TextButton(
              onPressed: isReconnecting ? null : () => _reconnectAccount(acc),
              style: TextButton.styleFrom(
                foregroundColor: palette.brand.deep,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: isReconnecting
                  ? SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: palette.brand.deep,
                      ),
                    )
                  : const Text(
                      UiStrings.accountReconnect,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
            ),
            const SizedBox(width: 4),
          ],
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 18),
            onPressed: () => _confirmRemove(context, acc),
          ),
        ],
      ),
    );
  }

  Future<void> _reconnectAccount(AccountRecord acc) async {
    final provider = acc.authType == 'oauth_microsoft'
        ? OAuthProvider.microsoft
        : OAuthProvider.google;

    setState(() => _reconnectingAccountIds.add(acc.id));
    final flow = ref.read(oauthFlowProvider);
    final repo = ref.read(accountRepositoryProvider);

    try {
      final tokens = await flow.authorize(provider);
      final auth = OAuth2MailAuth(
        tokens.accessToken,
        refreshToken: tokens.refreshToken,
        expiresAt: tokens.expiresAt,
        provider: provider,
      );

      await repo.saveAccount(acc, auth);
      repo.clearReauthRequired(acc.id);
      ref.read(mailRevisionProvider.notifier).bump();

      // Trigger sync
      final syncEngine = ref.read(syncEngineProvider);
      final errors = ref.read(syncErrorProvider.notifier);
      syncEngine.syncAccount(acc.id).catchError((Object e, StackTrace st) {
        logError('sync ${acc.email}', e, st);
        errors.set('Sync failed for ${acc.email}: $e');
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(UiStrings.accountReconnectSuccess)),
        );
      }
    } on OAuthCancelledException {
      // User cancelled sign-in - leaves account untouched, no error snackbar
    } catch (e, st) {
      logError('reconnect error for ${acc.email}', e, st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${AppStrings.setupFailed} ($e)'),
            duration: const Duration(seconds: 12),
            showCloseIcon: true,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _reconnectingAccountIds.remove(acc.id));
      }
    }
  }

  Future<void> _confirmRemove(BuildContext context, AccountRecord acc) async {
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
