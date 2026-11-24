import 'package:df_onboarding/df_onboarding.dart';
import 'package:spamfiltering_emailclient/app/strings.dart';
import 'package:spamfiltering_emailclient/app/ui_strings.dart';
import 'package:spamfiltering_emailclient/db/database.dart';
import 'package:spamfiltering_emailclient/funnel/launch_gate.dart';
import 'package:spamfiltering_emailclient/theme/app_brand.dart';
import 'package:spamfiltering_emailclient/ui/account_setup/account_setup_view.dart';
import 'package:spamfiltering_emailclient/ui/shell/nav_shell.dart';
import 'package:df_theme/df_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  // Load the bundled fonts; the default test font is far wider and overflows.
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

  Future<void> pumpGate(
    WidgetTester tester,
    Map<String, Object> prefs, {
    bool withAccount = false,
  }) async {
    SharedPreferences.setMockInitialValues(prefs);
    tester.view.physicalSize = const Size(1440, 900) * 1.5;
    tester.view.devicePixelRatio = 1.5;
    addTearDown(tester.view.reset);
    final db = await AppDatabase.open(inMemory: true);
    if (withAccount) {
      db.db.execute(
        'INSERT INTO accounts (id, email, display_name, imap_host, imap_port, '
        'smtp_host, smtp_port, auth_type, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
        ['acc_1', 'a@b.c', 'A', 'imap.b.c', 993, 'smtp.b.c', 587, 'password', DateTime.now().toIso8601String()],
      );
    }
    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: MaterialApp(
        theme: DfTheme.light(AppBrand.brand),
        home: const AppLaunchGate(child: AppNavShell()),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 600));
  }

  const done = {'flutter.df_funnel_onboarding_completed': true};

  testWidgets('fresh install goes onboarding (Skip) -> paywall ("Maybe later") -> Add Account', (tester) async {
    await pumpGate(tester, {});

    // Onboarding step from df_onboarding
    expect(find.byType(OnboardingScreen), findsOneWidget);
    expect(find.text(AppStrings.onbPage1Title), findsOneWidget);
    expect(find.text('Skip'), findsOneWidget);

    // Skip onboarding
    await tester.tap(find.text('Skip'));
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 600));
    }

    // Advances to paywall step
    expect(find.byType(OnboardingScreen), findsNothing);
    expect(find.text('Maybe later'), findsOneWidget);
    expect(find.text(UiStrings.upsellPoint1), findsOneWidget);

    // Skip paywall
    await tester.tap(find.text('Maybe later'));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 600));
    }

    // Opens Add Account
    expect(find.byType(AccountSetupView), findsOneWidget);
    expect(find.byType(AppNavShell, skipOffstage: false), findsOneWidget);
  });

  testWidgets('fresh install completes onboarding via carousel -> paywall', (tester) async {
    await pumpGate(tester, {});

    expect(find.byType(OnboardingScreen), findsOneWidget);
    expect(find.text(AppStrings.onbPage1Title), findsOneWidget);

    // Next to page 2
    await tester.tap(find.text('Next'));
    for (var i = 0; i < 2; i++) {
      await tester.pump(const Duration(milliseconds: 600));
    }
    expect(find.text(AppStrings.onbPage2Title), findsOneWidget);

    // Next to page 3
    await tester.tap(find.text('Next'));
    for (var i = 0; i < 2; i++) {
      await tester.pump(const Duration(milliseconds: 600));
    }
    expect(find.text(AppStrings.onbPage3Title), findsOneWidget);

    // Get Started on last page completes onboarding
    expect(find.text('Get Started'), findsOneWidget);
    await tester.tap(find.text('Get Started'));
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 600));
    }

    // Advances to paywall step
    expect(find.byType(OnboardingScreen), findsNothing);
    expect(find.text('Maybe later'), findsOneWidget);
  });

  testWidgets('paywall "Maybe later" opens Add Account when no account exists', (tester) async {
    await pumpGate(tester, done);

    // Paywall step (own Scaffold, not an unthemed page), explains Pro.
    expect(find.text('Maybe later'), findsOneWidget);
    expect(find.text(UiStrings.upsellPoint1), findsOneWidget);
    await tester.tap(find.text('Maybe later'));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 600));
    }

    // No login placeholder; straight to account setup, on top of the shell.
    expect(find.text('Skip for now'), findsNothing);
    expect(find.byType(AccountSetupView), findsOneWidget);
    expect(find.byType(AppNavShell, skipOffstage: false), findsOneWidget);
  });

  testWidgets('with an account, "Maybe later" goes straight to the app', (tester) async {
    await pumpGate(tester, done, withAccount: true);
    await tester.tap(find.text('Maybe later'));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.byType(AccountSetupView), findsNothing);
    expect(find.byType(AppNavShell), findsOneWidget);
  });
}
