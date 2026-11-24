import 'package:material_ui/material_ui.dart';
import 'package:df_settings/df_settings.dart';
import 'package:df_theme/df_theme.dart';
import '../../app/strings.dart';
import '../../app/ui_strings.dart';
import '../../theme/app_type.dart';
import '../premium/subscription_section.dart';
import '../premium/sync_tile.dart';
import 'accounts_tile.dart';
import 'appearance_tile.dart';
import 'notifications_tile.dart';
import 'sharing_tile.dart';

class SettingsView extends StatelessWidget {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    return DfSettingsScaffold(
      title: Text(
        AppStrings.settingsTitle,
        style: AppType.display(
          context.df.colors.textPrimary,
          size: 24,
          weight: 600,
          letterSpacing: -0.5,
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            children: const [
              DfSettingsGroup(
                title: UiStrings.settingsAccounts,
                children: [AccountsTile()],
              ),
              DfSettingsGroup(
                title: UiStrings.settingsNotifications,
                children: [NotificationsTile()],
              ),
              DfSettingsGroup(
                title: UiStrings.settingsPrivacy,
                children: [CommunitySharingTile()],
              ),
              DfSettingsGroup(
                title: UiStrings.settingsPro,
                children: [AppSubscriptionSection(), PremiumSyncTile()],
              ),
              DfSettingsGroup(
                title: UiStrings.settingsAppearance,
                children: [AppearanceTile()],
              ),
              DfLegalLinksSection(
                title: UiStrings.settingsLegal,
                privacyPolicyUrl:
                    'https://justinguese.github.io/flutter-spamfiltering-emailclient/concepts/privacy-model/',
                websiteUrl:
                    'https://justinguese.github.io/flutter-spamfiltering-emailclient/',
                showLicenses: true,
              ),
              DfVersionFooter(
                version: '1.0.0',
                buildNumber: '1',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
