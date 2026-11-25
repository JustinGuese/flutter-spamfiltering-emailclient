import 'package:df_funnel/df_funnel.dart';
import 'package:df_theme/df_theme.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spamfiltering_emailclient/app/strings.dart';
import 'package:spamfiltering_emailclient/app/ui_strings.dart';
import 'package:spamfiltering_emailclient/theme/app_brand.dart';
import 'package:spamfiltering_emailclient/ui/premium/premium_gate.dart';
import 'package:spamfiltering_emailclient/ui/premium/app_checkout.dart';
import 'package:spamfiltering_emailclient/ui/premium/app_upsell.dart';

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

  void configureTesterSize(WidgetTester tester) {
    tester.view.physicalSize = const Size(1440, 1080) * 1.5;
    tester.view.devicePixelRatio = 1.5;
    addTearDown(tester.view.reset);
  }

  Widget buildApp({
    required Widget child,
    bool isPro = false,
  }) {
    return ProviderScope(
      overrides: [
        dfEffectivePremiumProvider.overrideWithValue(isPro),
      ],
      child: MaterialApp(
        theme: DfTheme.light(AppBrand.brand),
        home: Scaffold(body: child),
      ),
    );
  }

  group('AppPremiumGate with DfPremiumGate integration', () {
    testWidgets('renders child when user is pro', (tester) async {
      configureTesterSize(tester);
      await tester.pumpWidget(buildApp(
        child: const AppPremiumGate(
          child: Text('Protected Pro Feature'),
        ),
        isPro: true,
      ));

      expect(find.text('Protected Pro Feature'), findsOneWidget);
      expect(find.byType(DfPremiumGate), findsOneWidget);
    });

    testWidgets('renders default lock overlay when not pro and opens upsell on tap', (tester) async {
      configureTesterSize(tester);
      await tester.pumpWidget(buildApp(
        child: const AppPremiumGate(
          child: Text('Protected Pro Feature'),
        ),
        isPro: false,
      ));

      expect(find.text('Protected Pro Feature'), findsNothing);
      expect(find.byIcon(Icons.lock_rounded), findsOneWidget);

      // Tap locked overlay to present paywall
      await tester.tap(find.byType(InkWell));
      await tester.pumpAndSettle();

      // DfUpsellSheet opens with honest pricing invariants
      expect(find.byType(DfUpsellSheet), findsOneWidget);
      expect(find.text(AppStrings.proAnnual), findsOneWidget);
      expect(find.text(UiStrings.upsellRenewal), findsOneWidget);
      expect(find.text(UiStrings.upsellLater), findsWidgets);
      expect(find.text(AppStrings.proUpgrade), findsOneWidget);

      // Dismissing sheet via close icon leaves feature locked
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();

      expect(find.byType(DfUpsellSheet), findsNothing);
      expect(find.text('Protected Pro Feature'), findsNothing);
    });

    testWidgets('renders custom lockedFallback and opens upsell on tap', (tester) async {
      configureTesterSize(tester);
      await tester.pumpWidget(buildApp(
        child: const AppPremiumGate(
          lockedFallback: Text('Custom Locked State'),
          child: Text('Protected Pro Feature'),
        ),
        isPro: false,
      ));

      expect(find.text('Protected Pro Feature'), findsNothing);
      expect(find.text('Custom Locked State'), findsOneWidget);

      await tester.tap(find.text('Custom Locked State'));
      await tester.pumpAndSettle();

      expect(find.byType(DfUpsellSheet), findsOneWidget);
    });

    Future<void> openUpsellAndTapUpgrade(WidgetTester tester) async {
      configureTesterSize(tester);
      await tester.pumpWidget(buildApp(
        child: const AppPremiumGate(
          child: Text('Protected Pro Feature'),
        ),
        isPro: false,
      ));
      await tester.tap(find.byType(InkWell));
      await tester.pumpAndSettle();
      expect(find.byType(DfUpsellSheet), findsOneWidget);
      await tester.tap(find.text(AppStrings.proUpgrade));
      await tester.pumpAndSettle();
    }

    tearDown(() {
      AppCheckout.debugPresenter = null;
      AppCheckout.debugIsDesktop = null;
    });

    testWidgets('a real purchase result unlocks locally via DfPremiumGate', (tester) async {
      String? seenPlacement;
      AppCheckout.debugPresenter = (ctx, {placement}) async {
        seenPlacement = placement;
        return DfPaywallResult.purchased;
      };
      await openUpsellAndTapUpgrade(tester);

      expect(seenPlacement, isNotNull);
      expect(find.byType(DfUpsellSheet), findsNothing);
      expect(find.text('Protected Pro Feature'), findsOneWidget);
    });

    testWidgets('upgrade never unlocks when the store flow is cancelled', (tester) async {
      AppCheckout.debugPresenter = (ctx, {placement}) async => DfPaywallResult.cancelled;
      await openUpsellAndTapUpgrade(tester);

      expect(find.text('Protected Pro Feature'), findsNothing);
      expect(find.byIcon(Icons.lock_rounded), findsOneWidget);
    });

    testWidgets('desktop has no checkout: no fake unlock, user is told why', (tester) async {
      AppCheckout.debugIsDesktop = true;
      await openUpsellAndTapUpgrade(tester);

      expect(find.text('Protected Pro Feature'), findsNothing);
      expect(find.text(UiStrings.checkoutDesktopUnavailable), findsOneWidget);
    });
  });

  group('DfUpsellSheet honest pricing invariants', () {
    testWidgets('displays visible price, renewal terms, and equal prominence buttons', (tester) async {
      configureTesterSize(tester);
      await tester.pumpWidget(buildApp(
        child: Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () => AppUpsell.show(ctx),
            child: const Text('Open Upsell'),
          ),
        ),
      ));

      await tester.tap(find.text('Open Upsell'));
      await tester.pumpAndSettle();

      // Price + renewal terms
      expect(find.text(AppStrings.proAnnual), findsOneWidget);
      expect(find.text(UiStrings.upsellRenewal), findsOneWidget);
      expect(find.text(UiStrings.upsellAnnual), findsOneWidget);

      // Equally prominent close button (OutlinedButton alongside FilledButton)
      expect(find.byType(OutlinedButton), findsOneWidget);
      expect(find.byType(FilledButton), findsOneWidget);
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    });

    testWidgets('maybeShow respects DfCooldown', (tester) async {
      configureTesterSize(tester);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      BuildContext? testContext;
      await tester.pumpWidget(buildApp(
        child: Builder(
          builder: (ctx) {
            testContext = ctx;
            return const SizedBox();
          },
        ),
      ));

      const cooldown = DfCooldown(
        key: 'test_upsell_cooldown',
        duration: Duration(hours: 1),
      );

      // First call shows
      final future1 = AppUpsell.maybeShow(
        testContext!,
        cooldown: cooldown,
        prefs: prefs,
      );
      await tester.pumpAndSettle();
      expect(find.byType(DfUpsellSheet), findsOneWidget);

      // Dismiss
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
      final shown1 = await future1;
      expect(shown1, isTrue);

      // Second immediate call is blocked by cooldown
      final shown2 = await AppUpsell.maybeShow(
        testContext!,
        cooldown: cooldown,
        prefs: prefs,
      );
      expect(shown2, isFalse);
    });
  });
}
