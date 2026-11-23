import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:df_theme/df_theme.dart';
import '../../app/strings.dart';
import '../../db/database.dart';

class CommunitySharingNotifier extends Notifier<bool> {
  @override
  bool build() {
    final db = ref.watch(databaseProvider);
    final row = db.db.select(
      "SELECT value FROM settings WHERE key = 'share_spam_fingerprints'",
    );
    if (row.isEmpty) return true;
    return row.first['value'] == 'true';
  }

  void toggle(bool val) {
    state = val;
    final db = ref.read(databaseProvider);
    db.db.execute('''
      INSERT OR REPLACE INTO settings (key, value)
      VALUES ('share_spam_fingerprints', ?)
    ''', [val.toString()]);
  }
}

final communitySharingEnabledProvider =
    NotifierProvider<CommunitySharingNotifier, bool>(CommunitySharingNotifier.new);

class CommunitySharingTile extends ConsumerWidget {
  const CommunitySharingTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(communitySharingEnabledProvider);
    final db = ref.watch(databaseProvider);
    final palette = context.df.colors;

    final verRow = db.db.select("SELECT value FROM settings WHERE key = 'blocklist_version'");
    final lastSyncRow = db.db.select("SELECT value FROM settings WHERE key = 'blocklist_last_sync'");
    final reportRow = db.db.select("SELECT value FROM settings WHERE key = 'last_report_at'");
    final version = verRow.firstOrNull?['value'] ?? 'v1.0';
    final lastSync = lastSyncRow.firstOrNull?['value'] ?? 'Never';
    final lastReport = reportRow.firstOrNull?['value'] ?? 'Never';

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
                  AppStrings.settingsSharing,
                  style: TextStyle(
                    fontFamily: 'Public Sans',
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: palette.textPrimary,
                  ),
                ),
              ),
              Switch(
                value: enabled,
                activeThumbColor: palette.brand.base,
                onChanged: (val) {
                  ref.read(communitySharingEnabledProvider.notifier).toggle(val);
                },
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            AppStrings.settingsSharingSub,
            style: TextStyle(
              fontFamily: 'Public Sans',
              fontSize: 12,
              color: palette.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${AppStrings.settingsBlocklistVer}: $version ($lastSync) · ${AppStrings.settingsLastReport}: $lastReport',
            style: TextStyle(
              fontFamily: 'JetBrains Mono',
              fontSize: 11,
              color: palette.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}
