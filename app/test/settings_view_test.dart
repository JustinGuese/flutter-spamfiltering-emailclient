import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:df_app_shell/df_app_shell.dart';
import 'package:df_theme/df_theme.dart';
import 'package:spamfiltering_emailclient/app/ui_strings.dart';
import 'package:spamfiltering_emailclient/db/database.dart';
import 'package:spamfiltering_emailclient/theme/app_brand.dart';
import 'package:spamfiltering_emailclient/ui/settings/appearance_tile.dart';
import 'package:spamfiltering_emailclient/ui/settings/notifications_tile.dart';
import 'package:spamfiltering_emailclient/ui/settings/settings_view.dart';
import 'package:spamfiltering_emailclient/ui/settings/sharing_tile.dart';

void main() {
  setUpAll(() async {
    for (final f in {
      'Fraunces': 'assets/fonts/Fraunces.ttf',
      'Public Sans': 'assets/fonts/PublicSans.ttf',
      'JetBrains Mono': 'assets/fonts/JetBrainsMono.ttf',
    }.entries) {
      final loader = FontLoader(f.key)..addFont(rootBundle.load(f.value));
      await loader.load();
    }
  });

  testWidgets('SettingsView renders NotificationsTile, CommunitySharingTile, AppearanceTile and default instant mode', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    tester.view.physicalSize = const Size(1440, 1600) * 1.5;
    tester.view.devicePixelRatio = 1.5;
    addTearDown(tester.view.reset);

    final db = await AppDatabase.open(inMemory: true);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: MaterialApp(
        theme: DfTheme.light(AppBrand.brand),
        home: const SettingsView(),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(NotificationsTile), findsOneWidget);
    expect(find.byType(CommunitySharingTile), findsOneWidget);
    expect(find.byType(AppearanceTile), findsOneWidget);
    expect(find.text(UiStrings.notifyModeInstant), findsOneWidget);
  });
}
