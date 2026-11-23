import 'package:material_ui/material_ui.dart';
import 'package:df_settings/df_settings.dart';
import 'package:df_theme/df_theme.dart';
import '../../app/strings.dart';
import '../../app/ui_strings.dart';
import '../../theme/app_type.dart';
import '../common/app_parts.dart';
import '../premium/subscription_section.dart';
import '../premium/sync_tile.dart';
import 'accounts_tile.dart';
import 'appearance_tile.dart';
import 'sharing_tile.dart';

class SettingsView extends StatelessWidget {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    return DfSettingsScaffold(
      title: Text(AppStrings.settingsTitle, style: AppType.display(context.df.colors.textPrimary, size: 24, weight: 600, letterSpacing: -0.5)),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: const [
          _Section(UiStrings.settingsAccounts, [AccountsTile()]),
          _Section(UiStrings.settingsPrivacy, [CommunitySharingTile()]),
          _Section(UiStrings.settingsPro, [AppSubscriptionSection(), PremiumSyncTile()]),
          _Section(UiStrings.settingsAppearance, [AppearanceTile()]),
          DfVersionFooter(
            version: '1.0.0',
            buildNumber: '1',
          ),
        ],
      ),
    );
  }
}

/// Eyebrow + a rounded card holding one or more tiles.
class _Section extends StatelessWidget {
  final String title;
  final List<Widget> tiles;
  const _Section(this.title, this.tiles);

  @override
  Widget build(BuildContext context) {
    final c = context.df.colors;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(padding: const EdgeInsets.fromLTRB(6, 0, 0, 10), child: Eyebrow(title)),
            Container(
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(context.df.shape.md),
                border: Border.all(color: c.hairline),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(children: tiles),
            ),
          ]),
        ),
      ),
    );
  }
}
