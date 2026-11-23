import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:df_funnel/df_funnel.dart';
import 'package:df_theme/df_theme.dart';
import '../../app/strings.dart';
import '../../db/database.dart';
import '../../premium/sync_key.dart';
import 'upsell_sheet.dart';

class PremiumSyncNotifier extends Notifier<bool> {
  @override
  bool build() {
    final db = ref.watch(databaseProvider);
    final row = db.db.select("SELECT value FROM settings WHERE key = 'filter_sync_enabled'");
    return row.isEmpty || row.first['value'] == 'true';
  }

  void toggle(bool val) async {
    state = val;
    final db = ref.read(databaseProvider);
    db.db.execute("INSERT OR REPLACE INTO settings (key, value) VALUES ('filter_sync_enabled', ?)", [val.toString()]);
    if (val) {
      await ref.read(syncKeyManagerProvider).getOrCreateKey();
    }
  }
}

final premiumSyncEnabledProvider = NotifierProvider<PremiumSyncNotifier, bool>(PremiumSyncNotifier.new);

class PremiumSyncTile extends ConsumerWidget {
  const PremiumSyncTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPro = ref.watch(dfEffectivePremiumProvider);
    final palette = context.df.colors;

    if (!isPro) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: palette.surface,
          border: Border(bottom: BorderSide(color: palette.hairline)),
        ),
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(AppStrings.settingsFilterSync, style: TextStyle(fontWeight: FontWeight.w600, color: palette.textPrimary)),
          subtitle: Text(AppStrings.settingsFilterSyncSub, style: TextStyle(fontSize: 12, color: palette.textSecondary)),
          trailing: OutlinedButton(
            onPressed: () => AppUpsellSheet.show(context),
            child: const Text(AppStrings.proUpgrade, style: TextStyle(fontSize: 12)),
          ),
        ),
      );
    }

    final enabled = ref.watch(premiumSyncEnabledProvider);
    final keyManager = ref.watch(syncKeyManagerProvider);

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
              Expanded(
                child: Text(
                  AppStrings.settingsFilterSync,
                  style: TextStyle(fontFamily: 'Public Sans', fontWeight: FontWeight.w600, fontSize: 14, color: palette.textPrimary),
                ),
              ),
              Switch(
                value: enabled,
                activeThumbColor: palette.brand.base,
                onChanged: (val) => ref.read(premiumSyncEnabledProvider.notifier).toggle(val),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(AppStrings.settingsFilterSyncSub, style: TextStyle(fontFamily: 'Public Sans', fontSize: 12, color: palette.textSecondary)),
          const SizedBox(height: 10),
          Row(
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.key_outlined, size: 14),
                label: const Text(AppStrings.syncRecoveryCode, style: TextStyle(fontSize: 11)),
                onPressed: () => _showRecoveryWordsDialog(context, keyManager),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.devices_outlined, size: 14),
                label: const Text(AppStrings.syncAddDevice, style: TextStyle(fontSize: 11)),
                onPressed: () => _showImportDialog(context, keyManager),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showRecoveryWordsDialog(BuildContext context, SyncKeyManager keyManager) async {
    final words = await keyManager.exportRecoveryWords();
    if (!context.mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(AppStrings.syncRecoveryCode),
        content: SelectableText(
          words.join(' '),
          style: const TextStyle(fontFamily: 'JetBrains Mono', fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: words.join(' ')));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(AppStrings.syncWordsCopied)));
              Navigator.of(ctx).pop();
            },
            child: const Text(AppStrings.syncWordsCopied),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(AppStrings.syncClose),
          ),
        ],
      ),
    );
  }

  void _showImportDialog(BuildContext context, SyncKeyManager keyManager) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(AppStrings.syncAddDevice),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(labelText: AppStrings.syncEnterWordsHint),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(AppStrings.syncCancel),
          ),
          FilledButton(
            onPressed: () async {
              final text = ctrl.text.trim();
              if (text.isNotEmpty) {
                final list = text.split(RegExp(r'\s+'));
                await keyManager.importRecoveryWords(list);
                if (ctx.mounted) {
                  Navigator.of(ctx).pop();
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(AppStrings.syncImportSuccess)));
                }
              }
            },
            child: const Text(AppStrings.syncImport),
          ),
        ],
      ),
    );
  }
}
