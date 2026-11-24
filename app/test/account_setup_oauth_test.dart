import 'package:df_theme/df_theme.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:spamfiltering_emailclient/app/strings.dart';
import 'package:spamfiltering_emailclient/app/ui_strings.dart';
import 'package:spamfiltering_emailclient/db/database.dart';
import 'package:spamfiltering_emailclient/mail/account_repository.dart';
import 'package:spamfiltering_emailclient/mail/mail_auth.dart';
import 'package:spamfiltering_emailclient/mail/oauth/oauth_flow.dart';
import 'package:spamfiltering_emailclient/mail/sync_engine.dart';
import 'package:spamfiltering_emailclient/theme/app_brand.dart';
import 'package:spamfiltering_emailclient/ui/account_setup/account_setup_view.dart';
import 'package:spamfiltering_emailclient/ui/settings/accounts_tile.dart';
import 'package:sqlite3/sqlite3.dart';

class _InMemorySecureStorage implements FlutterSecureStorage {
  final Map<String, String> values = {};

  @override
  Future<String?> read({required String key, dynamic iOptions, dynamic aOptions, dynamic lOptions, dynamic webOptions, dynamic mOptions, dynamic wOptions}) async =>
      values[key];

  @override
  Future<void> write({required String key, required String? value, dynamic iOptions, dynamic aOptions, dynamic lOptions, dynamic webOptions, dynamic mOptions, dynamic wOptions}) async {
    if (value != null) {
      values[key] = value;
    } else {
      values.remove(key);
    }
  }

  @override
  Future<void> delete({required String key, dynamic iOptions, dynamic aOptions, dynamic lOptions, dynamic webOptions, dynamic mOptions, dynamic wOptions}) async {
    values.remove(key);
  }

  @override
  Future<void> deleteAll({dynamic iOptions, dynamic aOptions, dynamic lOptions, dynamic webOptions, dynamic mOptions, dynamic wOptions}) async {
    values.clear();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeOAuthFlow implements OAuthFlow {
  OAuthTokens? tokensToReturn;
  Object? errorToThrow;
  int authorizeCallCount = 0;
  OAuthProvider? lastProvider;

  @override
  Future<OAuthTokens> authorize(OAuthProvider p) async {
    authorizeCallCount++;
    lastProvider = p;
    if (errorToThrow != null) {
      throw errorToThrow!;
    }
    return tokensToReturn ??
        OAuthTokens(
          accessToken: 'fake_access_token',
          refreshToken: 'fake_refresh_token',
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
        );
  }
}

class _FakeSyncEngine extends SyncEngine {
  _FakeSyncEngine({required super.db, required super.accountRepo});

  int syncCallCount = 0;

  @override
  Future<void> syncAccount(String accountId) async {
    syncCallCount++;
  }
}

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

  late AppDatabase db;
  late _InMemorySecureStorage storage;
  late AccountRepository repo;
  late _FakeOAuthFlow fakeOAuthFlow;
  late _FakeSyncEngine fakeSyncEngine;

  setUp(() {
    db = AppDatabase(sqlite3.openInMemory());
    storage = _InMemorySecureStorage();
    fakeOAuthFlow = _FakeOAuthFlow();
    repo = AccountRepository(db: db, storage: storage);
    fakeSyncEngine = _FakeSyncEngine(db: db, accountRepo: repo);
  });

  tearDown(() {
    db.close();
  });

  Widget buildTestWidget(Widget child, {WidgetTester? tester}) {
    if (tester != null) {
      tester.view.physicalSize = const Size(1440, 900) * 1.5;
      tester.view.devicePixelRatio = 1.5;
      addTearDown(tester.view.reset);
    }
    return ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        accountRepositoryProvider.overrideWithValue(repo),
        oauthFlowProvider.overrideWithValue(fakeOAuthFlow),
        syncEngineProvider.overrideWithValue(fakeSyncEngine),
      ],
      child: MaterialApp(
        theme: DfTheme.light(AppBrand.brand),
        home: Scaffold(body: child),
      ),
    );
  }

  group('AccountSetupView OAuth UI', () {
    testWidgets('renders Google and Microsoft buttons and app-password note', (tester) async {
      await tester.pumpWidget(buildTestWidget(const AccountSetupView(), tester: tester));
      await tester.pumpAndSettle();

      expect(find.text(UiStrings.setupContinueGoogle), findsOneWidget);
      expect(find.text(UiStrings.setupContinueMicrosoft), findsOneWidget);
      expect(find.text(UiStrings.setupOrDivider), findsOneWidget);
      expect(find.text(AppStrings.setupAppPasswordNote), findsOneWidget);
      expect(find.text(AppStrings.setupConnect), findsOneWidget);
    });

    testWidgets('unconfigured Google shows not-configured snackbar without saving account', (tester) async {
      await tester.pumpWidget(buildTestWidget(const AccountSetupView(), tester: tester));
      await tester.pumpAndSettle();

      await tester.tap(find.text(UiStrings.setupContinueGoogle));
      await tester.pump();

      expect(find.text(UiStrings.setupGoogleNotConfigured), findsOneWidget);
      expect(repo.listAccounts(), isEmpty);
    });

    testWidgets('unconfigured Microsoft shows not-configured snackbar without saving account', (tester) async {
      await tester.pumpWidget(buildTestWidget(const AccountSetupView(), tester: tester));
      await tester.pumpAndSettle();

      await tester.tap(find.text(UiStrings.setupContinueMicrosoft));
      await tester.pump();

      expect(find.text(UiStrings.setupMicrosoftNotConfigured), findsOneWidget);
      expect(repo.listAccounts(), isEmpty);
    });

    testWidgets('cancelled OAuth sign-in leaves no half-saved account and shows no error snackbar', (tester) async {
      fakeOAuthFlow.errorToThrow = const OAuthCancelledException('User closed window');

      await tester.pumpWidget(buildTestWidget(const AccountSetupView(), tester: tester));
      await tester.pumpAndSettle();

      expect(repo.listAccounts(), isEmpty);
      expect(find.byType(SnackBar), findsNothing);
    });
  });

  group('AccountsTile Reconnect UI', () {
    testWidgets('displays account and shows Reconnect button when re-auth is needed', (tester) async {
      final acc = AccountRecord(
        id: 'acc_ms_1',
        email: 'user@outlook.com',
        displayName: 'Test Outlook',
        imapHost: 'outlook.office365.com',
        imapPort: 993,
        smtpHost: 'smtp-mail.outlook.com',
        smtpPort: 587,
        authType: 'oauth_microsoft',
        createdAt: DateTime.now(),
      );

      await repo.saveAccount(
        acc,
        OAuth2MailAuth(
          'old_token',
          refreshToken: 'old_refresh',
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
          provider: OAuthProvider.microsoft,
        ),
      );

      // Initially no reconnect needed
      await tester.pumpWidget(buildTestWidget(const SingleChildScrollView(child: AccountsTile()), tester: tester));
      await tester.pumpAndSettle();
      expect(find.text('Test Outlook'), findsOneWidget);
      expect(find.text('user@outlook.com'), findsOneWidget);
      expect(find.text(UiStrings.accountReconnect), findsNothing);

      // Mark re-auth required
      repo.markReauthRequired('acc_ms_1');
      await tester.pumpWidget(buildTestWidget(const SingleChildScrollView(child: AccountsTile()), tester: tester));
      await tester.pumpAndSettle();

      expect(find.text(UiStrings.accountNeedsReauth), findsOneWidget);
      expect(find.text(UiStrings.accountReconnect), findsOneWidget);
    });

    testWidgets('tapping Reconnect runs flow.authorize and updates credentials', (tester) async {
      final acc = AccountRecord(
        id: 'acc_goog_1',
        email: 'user@gmail.com',
        displayName: 'Test Google',
        imapHost: 'imap.gmail.com',
        imapPort: 993,
        smtpHost: 'smtp.gmail.com',
        smtpPort: 587,
        authType: 'oauth_google',
        createdAt: DateTime.now(),
      );

      await repo.saveAccount(
        acc,
        OAuth2MailAuth(
          'old_token',
          refreshToken: 'old_refresh',
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
          provider: OAuthProvider.google,
        ),
      );
      repo.markReauthRequired('acc_goog_1');

      fakeOAuthFlow.tokensToReturn = OAuthTokens(
        accessToken: 'brand_new_token',
        refreshToken: 'brand_new_refresh',
        expiresAt: DateTime.now().add(const Duration(hours: 2)),
      );

      await tester.pumpWidget(buildTestWidget(const SingleChildScrollView(child: AccountsTile()), tester: tester));
      await tester.pumpAndSettle();
      expect(find.text(UiStrings.accountReconnect), findsOneWidget);

      await tester.tap(find.text(UiStrings.accountReconnect));
      await tester.pumpAndSettle();

      expect(fakeOAuthFlow.authorizeCallCount, 1);
      expect(fakeOAuthFlow.lastProvider, OAuthProvider.google);
      expect(repo.isReauthRequired('acc_goog_1'), isFalse);
      expect(storage.values['auth_oauth_token_acc_goog_1'], 'brand_new_token');
      expect(storage.values['auth_oauth_refresh_acc_goog_1'], 'brand_new_refresh');
    });

    testWidgets('cancelled reconnect leaves account intact without error snackbar', (tester) async {
      final acc = AccountRecord(
        id: 'acc_goog_2',
        email: 'user2@gmail.com',
        displayName: 'Test Google 2',
        imapHost: 'imap.gmail.com',
        imapPort: 993,
        smtpHost: 'smtp.gmail.com',
        smtpPort: 587,
        authType: 'oauth_google',
        createdAt: DateTime.now(),
      );

      await repo.saveAccount(
        acc,
        OAuth2MailAuth(
          'old_token',
          refreshToken: 'old_refresh',
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
          provider: OAuthProvider.google,
        ),
      );
      repo.markReauthRequired('acc_goog_2');

      fakeOAuthFlow.errorToThrow = const OAuthCancelledException('User closed tab');

      await tester.pumpWidget(buildTestWidget(const SingleChildScrollView(child: AccountsTile()), tester: tester));
      await tester.pumpAndSettle();
      await tester.tap(find.text(UiStrings.accountReconnect));
      await tester.pumpAndSettle();

      expect(storage.values['auth_oauth_token_acc_goog_2'], 'old_token');
      expect(find.byType(SnackBar), findsNothing);
    });
  });
}
