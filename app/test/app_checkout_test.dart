import 'package:df_billing/df_billing.dart';
import 'package:df_funnel/df_funnel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:spamfiltering_emailclient/app/ui_strings.dart';
import 'package:spamfiltering_emailclient/ui/premium/app_checkout.dart';

void main() {
  Widget buildTestContext(void Function(BuildContext) onBuild) {
    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) {
            onBuild(context);
            return const SizedBox();
          },
        ),
      ),
    );
  }

  setUp(() {
    AppCheckout.debugPresenter = null;
    AppCheckout.debugIsDesktop = null;
    AppCheckout.debugIsFirebaseConfigured = null;
    AppCheckout.debugAuthGate = null;
    AppCheckout.debugLauncher = null;
    AppCheckout.debugWebLinkOpener = null;
    AppCheckout.debugRcWebPurchaseLink = null;
    AppCheckout.debugRevenueCatLogIn = null;
  });

  tearDown(() {
    AppCheckout.debugPresenter = null;
    AppCheckout.debugIsDesktop = null;
    AppCheckout.debugIsFirebaseConfigured = null;
    AppCheckout.debugAuthGate = null;
    AppCheckout.debugLauncher = null;
    AppCheckout.debugWebLinkOpener = null;
    AppCheckout.debugRcWebPurchaseLink = null;
    AppCheckout.debugRevenueCatLogIn = null;
  });

  group('AppCheckout Firebase configuration check', () {
    testWidgets('unconfigured build shows checkoutUnavailable and returns notPresented', (tester) async {
      AppCheckout.debugIsFirebaseConfigured = false;
      BuildContext? capturedContext;

      await tester.pumpWidget(buildTestContext((ctx) => capturedContext = ctx));

      final result = await AppCheckout.present(capturedContext!);
      await tester.pump();

      expect(result, equals(DfPaywallResult.notPresented));
      expect(find.text(UiStrings.checkoutUnavailable), findsOneWidget);
    });
  });

  group('AppCheckout signed-out behaviour', () {
    testWidgets('signed-out cancelling sign-in yields cancelled without opening paywall or browser (native)', (tester) async {
      AppCheckout.debugIsFirebaseConfigured = true;
      AppCheckout.debugIsDesktop = false;

      bool paywallOpened = false;
      AppCheckout.debugLauncher = (ctx, {placement}) async {
        paywallOpened = true;
        return DfPaywallResult.purchased;
      };

      // Sign-in was cancelled / dismissed (returned null)
      AppCheckout.debugAuthGate = (ctx) async => null;

      BuildContext? capturedContext;
      await tester.pumpWidget(buildTestContext((ctx) => capturedContext = ctx));

      final result = await AppCheckout.present(capturedContext!);
      await tester.pump();

      expect(result, equals(DfPaywallResult.cancelled));
      expect(paywallOpened, isFalse);
    });

    testWidgets('signed-out cancelling sign-in yields cancelled without opening browser (desktop)', (tester) async {
      AppCheckout.debugIsFirebaseConfigured = true;
      AppCheckout.debugIsDesktop = true;

      bool browserOpened = false;
      AppCheckout.debugWebLinkOpener = ({required baseLink, required appUserId, email}) async {
        browserOpened = true;
        return const DfCheckoutResult.success();
      };

      AppCheckout.debugAuthGate = (ctx) async => null;

      BuildContext? capturedContext;
      await tester.pumpWidget(buildTestContext((ctx) => capturedContext = ctx));

      final result = await AppCheckout.present(capturedContext!);
      await tester.pump();

      expect(result, equals(DfPaywallResult.cancelled));
      expect(browserOpened, isFalse);
    });
  });

  group('AppCheckout signed-in native behaviour', () {
    testWidgets('signed-in native calls DfRevenueCat.logIn and launcher', (tester) async {
      AppCheckout.debugIsFirebaseConfigured = true;
      AppCheckout.debugIsDesktop = false;
      AppCheckout.debugAuthGate = (ctx) async => 'user-123';

      String? loggedInUid;
      AppCheckout.debugRevenueCatLogIn = (uid) async {
        loggedInUid = uid;
      };

      String? launchedPlacement;
      AppCheckout.debugLauncher = (ctx, {placement}) async {
        launchedPlacement = placement;
        return DfPaywallResult.purchased;
      };

      BuildContext? capturedContext;
      await tester.pumpWidget(buildTestContext((ctx) => capturedContext = ctx));

      final result = await AppCheckout.present(capturedContext!, placement: 'custom_placement');
      await tester.pump();

      expect(result, equals(DfPaywallResult.purchased));
      expect(loggedInUid, equals('user-123'));
      expect(launchedPlacement, equals('custom_placement'));
    });

    testWidgets('a failed RevenueCat logIn never opens the paywall (no anonymous purchase)', (tester) async {
      AppCheckout.debugIsFirebaseConfigured = true;
      AppCheckout.debugIsDesktop = false;
      AppCheckout.debugAuthGate = (ctx) async => 'user-123';
      AppCheckout.debugRevenueCatLogIn = (uid) async => false; // logIn failed

      var paywallShown = false;
      AppCheckout.debugLauncher = (ctx, {placement}) async {
        paywallShown = true;
        return DfPaywallResult.purchased;
      };

      BuildContext? capturedContext;
      await tester.pumpWidget(buildTestContext((ctx) => capturedContext = ctx));

      final result = await AppCheckout.present(capturedContext!);
      await tester.pump();

      expect(paywallShown, isFalse);
      expect(result, equals(DfPaywallResult.error));
      expect(find.text(UiStrings.checkoutUnavailable), findsOneWidget);
    });

    testWidgets('native paywall error shows snackbar and returns error', (tester) async {
      AppCheckout.debugIsFirebaseConfigured = true;
      AppCheckout.debugIsDesktop = false;
      AppCheckout.debugAuthGate = (ctx) async => 'user-123';
      AppCheckout.debugRevenueCatLogIn = (uid) async {};
      AppCheckout.debugLauncher = (ctx, {placement}) async => DfPaywallResult.error;

      BuildContext? capturedContext;
      await tester.pumpWidget(buildTestContext((ctx) => capturedContext = ctx));

      final result = await AppCheckout.present(capturedContext!);
      await tester.pump();

      expect(result, equals(DfPaywallResult.error));
      expect(find.text(UiStrings.checkoutUnavailable), findsOneWidget);
    });
  });

  group('AppCheckout signed-in desktop behaviour', () {
    testWidgets('desktop opens web purchase link with uid and does NOT unlock (returns notPresented)', (tester) async {
      AppCheckout.debugIsFirebaseConfigured = true;
      AppCheckout.debugIsDesktop = true;
      AppCheckout.debugRcWebPurchaseLink = 'https://pay.rev.cat/test_token/';
      AppCheckout.debugAuthGate = (ctx) async => 'desktop-uid-789';

      String? passedBaseLink;
      String? passedAppUserId;
      AppCheckout.debugWebLinkOpener = ({required baseLink, required appUserId, email}) async {
        passedBaseLink = baseLink;
        passedAppUserId = appUserId;
        return const DfCheckoutResult.success();
      };

      BuildContext? capturedContext;
      await tester.pumpWidget(buildTestContext((ctx) => capturedContext = ctx));

      final result = await AppCheckout.present(capturedContext!);
      await tester.pump();

      // Entitlement arrives through fetcher on resume — NEVER report purchased from browser launch
      expect(result, equals(DfPaywallResult.notPresented));
      expect(passedBaseLink, equals('https://pay.rev.cat/test_token/'));
      expect(passedAppUserId, equals('desktop-uid-789'));
    });

    testWidgets('desktop failed link open shows snackbar', (tester) async {
      AppCheckout.debugIsFirebaseConfigured = true;
      AppCheckout.debugIsDesktop = true;
      AppCheckout.debugRcWebPurchaseLink = 'https://pay.rev.cat/test_token/';
      AppCheckout.debugAuthGate = (ctx) async => 'desktop-uid-789';

      AppCheckout.debugWebLinkOpener = ({required baseLink, required appUserId, email}) async {
        return const DfCheckoutResult.failed(DfCheckoutFailure.launchFailed);
      };

      BuildContext? capturedContext;
      await tester.pumpWidget(buildTestContext((ctx) => capturedContext = ctx));

      final result = await AppCheckout.present(capturedContext!);
      await tester.pump();

      expect(result, equals(DfPaywallResult.notPresented));
      expect(find.text(UiStrings.checkoutUnavailable), findsOneWidget);
    });
  });
}
