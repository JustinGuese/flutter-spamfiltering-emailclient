import 'dart:async';
import 'package:df_oauth/df_oauth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spamfiltering_emailclient/db/database.dart';
import 'package:spamfiltering_emailclient/mail/account_repository.dart';
import 'package:spamfiltering_emailclient/mail/mail_auth.dart';
import 'package:spamfiltering_emailclient/mail/oauth/oauth_service.dart';
import 'package:spamfiltering_emailclient/mail/oauth/oauth_types.dart';
import 'package:sqlite3/sqlite3.dart';

class _InMemorySecureStorage implements FlutterSecureStorage {
  final Map<String, String> values = {};

  @override
  Future<String?> read({
    required String key,
    dynamic iOptions,
    dynamic aOptions,
    dynamic lOptions,
    dynamic webOptions,
    dynamic mOptions,
    dynamic wOptions,
  }) async =>
      values[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    dynamic iOptions,
    dynamic aOptions,
    dynamic lOptions,
    dynamic webOptions,
    dynamic mOptions,
    dynamic wOptions,
  }) async {
    if (value != null) {
      values[key] = value;
    } else {
      values.remove(key);
    }
  }

  @override
  Future<void> delete({
    required String key,
    dynamic iOptions,
    dynamic aOptions,
    dynamic lOptions,
    dynamic webOptions,
    dynamic mOptions,
    dynamic wOptions,
  }) async {
    values.remove(key);
  }

  @override
  Future<void> deleteAll({
    dynamic iOptions,
    dynamic aOptions,
    dynamic lOptions,
    dynamic webOptions,
    dynamic mOptions,
    dynamic wOptions,
  }) async {
    values.clear();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeOAuthService extends OAuthService {
  int refreshCallCount = 0;
  OAuthTokens? returnTokens;
  Object? errorToThrow;
  Duration delay = Duration.zero;
  final List<String> flightKeys = [];

  @override
  Future<OAuthTokens> refresh({
    required OAuthProvider provider,
    required String refreshToken,
    String accountId = '',
    String email = '',
    DfOAuthProviderConfig? configOverride,
    String? flightKey,
  }) async {
    refreshCallCount++;
    if (flightKey != null) {
      flightKeys.add(flightKey);
    }
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }
    if (errorToThrow != null) {
      if (errorToThrow is DfOAuthInvalidGrantException) {
        throw ReauthRequiredException(
          accountId: accountId,
          email: email,
          provider: provider,
        );
      }
      throw errorToThrow!;
    }
    return returnTokens ??
        OAuthTokens(
          accessToken: 'fresh_access_token',
          refreshToken: 'fresh_refresh_token',
          expiresAt: DateTime(2026, 11, 24, 15, 0, 0),
        );
  }
}

void main() {
  late AppDatabase db;
  late _InMemorySecureStorage storage;
  late _FakeOAuthService fakeOAuth;
  late DateTime fixedNow;
  late AccountRepository repo;

  setUp(() {
    db = AppDatabase(sqlite3.openInMemory());
    storage = _InMemorySecureStorage();
    fakeOAuth = _FakeOAuthService();
    fixedNow = DateTime(2026, 11, 24, 12, 0, 0);

    repo = AccountRepository(
      db: db,
      storage: storage,
      oauthService: fakeOAuth,
      now: () => fixedNow,
    );

    db.db.execute('''
      INSERT INTO accounts (id, email, display_name, imap_host, imap_port, smtp_host, smtp_port, auth_type, created_at)
      VALUES ('acc_google', 'user@gmail.com', 'Google User', 'imap.gmail.com', 993, 'smtp.gmail.com', 587, 'oauth_google', '2026-11-20T00:00:00Z')
    ''');
    db.db.execute('''
      INSERT INTO accounts (id, email, display_name, imap_host, imap_port, smtp_host, smtp_port, auth_type, created_at)
      VALUES ('acc_ms', 'user@outlook.com', 'MS User', 'outlook.office365.com', 993, 'smtp-mail.outlook.com', 587, 'oauth_microsoft', '2026-11-20T00:00:00Z')
    ''');
  });

  tearDown(() {
    db.close();
  });

  group('AccountRepository OAuth', () {
    test('expired token refreshed and persisted', () async {
      storage.values['auth_oauth_token_acc_google'] = 'expired_access_token';
      storage.values['auth_oauth_refresh_acc_google'] = 'valid_refresh_token';
      // Expired 1 hour ago
      storage.values['auth_oauth_expires_acc_google'] =
          fixedNow.subtract(const Duration(hours: 1)).toIso8601String();
      storage.values['auth_oauth_provider_acc_google'] = 'google';

      final auth = await repo.getAuthForAccount('acc_google');

      expect(auth, isA<OAuth2MailAuth>());
      final oauthAuth = auth as OAuth2MailAuth;
      expect(oauthAuth.accessToken, 'fresh_access_token');
      expect(oauthAuth.refreshToken, 'fresh_refresh_token');
      expect(oauthAuth.expiresAt, DateTime(2026, 11, 24, 15, 0, 0));
      expect(oauthAuth.provider, OAuthProvider.google);

      // Verify refreshed tokens were persisted to secure storage
      expect(storage.values['auth_oauth_token_acc_google'], 'fresh_access_token');
      expect(storage.values['auth_oauth_refresh_acc_google'], 'fresh_refresh_token');
      expect(storage.values['auth_oauth_expires_acc_google'],
          DateTime(2026, 11, 24, 15, 0, 0).toIso8601String());
      expect(storage.values['auth_oauth_provider_acc_google'], 'google');
      expect(fakeOAuth.refreshCallCount, 1);
    });

    test('token expiring in < 2 minutes is refreshed', () async {
      storage.values['auth_oauth_token_acc_google'] = 'soon_expired_token';
      storage.values['auth_oauth_refresh_acc_google'] = 'valid_refresh_token';
      // Expiring in 90 seconds (< 2 minutes buffer)
      storage.values['auth_oauth_expires_acc_google'] =
          fixedNow.add(const Duration(seconds: 90)).toIso8601String();
      storage.values['auth_oauth_provider_acc_google'] = 'google';

      final auth = await repo.getAuthForAccount('acc_google');

      expect(auth, isA<OAuth2MailAuth>());
      expect((auth as OAuth2MailAuth).accessToken, 'fresh_access_token');
      expect(fakeOAuth.refreshCallCount, 1);
      expect(storage.values['auth_oauth_token_acc_google'], 'fresh_access_token');
    });

    test('legacy token without expiresAt is treated as expired', () async {
      storage.values['auth_oauth_token_acc_google'] = 'legacy_access_token';
      storage.values['auth_oauth_refresh_acc_google'] = 'legacy_refresh_token';
      // No auth_oauth_expires key!

      final auth = await repo.getAuthForAccount('acc_google');

      expect(auth, isA<OAuth2MailAuth>());
      final oauthAuth = auth as OAuth2MailAuth;
      expect(oauthAuth.accessToken, 'fresh_access_token');
      expect(fakeOAuth.refreshCallCount, 1);
      expect(storage.values['auth_oauth_expires_acc_google'], isNotNull);
    });

    test('valid token untouched (no refresh)', () async {
      final validExpiry = fixedNow.add(const Duration(hours: 1));
      storage.values['auth_oauth_token_acc_google'] = 'valid_access_token';
      storage.values['auth_oauth_refresh_acc_google'] = 'valid_refresh_token';
      storage.values['auth_oauth_expires_acc_google'] = validExpiry.toIso8601String();
      storage.values['auth_oauth_provider_acc_google'] = 'google';

      final auth = await repo.getAuthForAccount('acc_google');

      expect(auth, isA<OAuth2MailAuth>());
      final oauthAuth = auth as OAuth2MailAuth;
      expect(oauthAuth.accessToken, 'valid_access_token');
      expect(oauthAuth.refreshToken, 'valid_refresh_token');
      expect(oauthAuth.expiresAt, validExpiry);
      expect(oauthAuth.provider, OAuthProvider.google);
      expect(fakeOAuth.refreshCallCount, 0);
    });

    test('concurrent calls share one in-flight refresh', () async {
      storage.values['auth_oauth_token_acc_google'] = 'expired_token';
      storage.values['auth_oauth_refresh_acc_google'] = 'valid_refresh_token';
      storage.values['auth_oauth_expires_acc_google'] =
          fixedNow.subtract(const Duration(minutes: 5)).toIso8601String();
      storage.values['auth_oauth_provider_acc_google'] = 'google';

      fakeOAuth.delay = const Duration(milliseconds: 60);

      // Fire 5 concurrent calls to getAuthForAccount
      final futures = [
        repo.getAuthForAccount('acc_google'),
        repo.getAuthForAccount('acc_google'),
        repo.getAuthForAccount('acc_google'),
        repo.getAuthForAccount('acc_google'),
        repo.getAuthForAccount('acc_google'),
      ];

      final results = await Future.wait(futures);

      expect(fakeOAuth.refreshCallCount, 1);
      for (final res in results) {
        expect(res, isA<OAuth2MailAuth>());
        expect((res as OAuth2MailAuth).accessToken, 'fresh_access_token');
      }
    });

    test('refresh failure with invalid_grant throws ReauthRequiredException', () async {
      storage.values['auth_oauth_token_acc_ms'] = 'expired_ms_token';
      storage.values['auth_oauth_refresh_acc_ms'] = 'revoked_ms_refresh';
      storage.values['auth_oauth_expires_acc_ms'] =
          fixedNow.subtract(const Duration(minutes: 10)).toIso8601String();
      storage.values['auth_oauth_provider_acc_ms'] = 'microsoft';

      fakeOAuth.errorToThrow = const DfOAuthInvalidGrantException('Revoked');

      expect(
        () => repo.getAuthForAccount('acc_ms'),
        throwsA(
          isA<ReauthRequiredException>()
              .having((e) => e.accountId, 'accountId', 'acc_ms')
              .having((e) => e.email, 'email', 'user@outlook.com')
              .having((e) => e.provider, 'provider', OAuthProvider.microsoft),
        ),
      );
    });

    test('refresh without refresh token throws ReauthRequiredException', () async {
      storage.values['auth_oauth_token_acc_google'] = 'expired_token';
      // Missing refresh token
      storage.values['auth_oauth_expires_acc_google'] =
          fixedNow.subtract(const Duration(minutes: 1)).toIso8601String();

      expect(
        () => repo.getAuthForAccount('acc_google'),
        throwsA(
          isA<ReauthRequiredException>()
              .having((e) => e.accountId, 'accountId', 'acc_google')
              .having((e) => e.email, 'email', 'user@gmail.com')
              .having((e) => e.provider, 'provider', OAuthProvider.google),
        ),
      );
    });

    test('saveAccount and deleteAccount handle new keys', () async {
      final acc = AccountRecord(
        id: 'acc_new',
        email: 'new@example.com',
        displayName: 'New User',
        imapHost: 'imap.example.com',
        imapPort: 993,
        smtpHost: 'smtp.example.com',
        smtpPort: 587,
        authType: 'oauth_microsoft',
        createdAt: DateTime(2026, 11, 24),
      );

      final expiry = fixedNow.add(const Duration(hours: 2));
      await repo.saveAccount(
        acc,
        OAuth2MailAuth(
          'token_new',
          refreshToken: 'refresh_new',
          expiresAt: expiry,
          provider: OAuthProvider.microsoft,
        ),
      );

      expect(storage.values['auth_oauth_token_acc_new'], 'token_new');
      expect(storage.values['auth_oauth_refresh_acc_new'], 'refresh_new');
      expect(storage.values['auth_oauth_expires_acc_new'], expiry.toIso8601String());
      expect(storage.values['auth_oauth_provider_acc_new'], 'microsoft');

      // Now delete account
      await repo.deleteAccount('acc_new');

      expect(storage.values['auth_oauth_token_acc_new'], isNull);
      expect(storage.values['auth_oauth_refresh_acc_new'], isNull);
      expect(storage.values['auth_oauth_expires_acc_new'], isNull);
      expect(storage.values['auth_oauth_provider_acc_new'], isNull);
    });

    test('existing password accounts behave exactly as before', () async {
      final acc = AccountRecord(
        id: 'acc_pass',
        email: 'pass@example.com',
        displayName: 'Password User',
        imapHost: 'imap.example.com',
        imapPort: 993,
        smtpHost: 'smtp.example.com',
        smtpPort: 587,
        authType: 'password',
        createdAt: DateTime(2026, 11, 24),
      );

      await repo.saveAccount(acc, const PasswordMailAuth('secret_pass'));
      expect(storage.values['auth_pass_acc_pass'], 'secret_pass');

      final auth = await repo.getAuthForAccount('acc_pass');
      expect(auth, isA<PasswordMailAuth>());
      expect((auth as PasswordMailAuth).password, 'secret_pass');
      expect(fakeOAuth.refreshCallCount, 0);

      await repo.deleteAccount('acc_pass');
      expect(storage.values['auth_pass_acc_pass'], isNull);
    });
  });
}
