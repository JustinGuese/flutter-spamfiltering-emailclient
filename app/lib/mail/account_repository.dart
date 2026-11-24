import 'package:df_oauth/df_oauth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../app/log.dart';
import '../db/database.dart';
import 'attachments.dart';
import 'mail_auth.dart';
import 'oauth/oauth_service.dart';
import 'oauth/oauth_types.dart';

class AccountRecord {
  final String id;
  final String email;
  final String displayName;
  final String imapHost;
  final int imapPort;
  final String smtpHost;
  final int smtpPort;
  final String authType;
  final DateTime createdAt;

  const AccountRecord({
    required this.id,
    required this.email,
    required this.displayName,
    required this.imapHost,
    required this.imapPort,
    required this.smtpHost,
    required this.smtpPort,
    required this.authType,
    required this.createdAt,
  });
}

class AccountRepository {
  final AppDatabase db;
  final FlutterSecureStorage secureStorage;

  /// Downloaded attachments; removed with the account. Null in tests that
  /// never download one.
  final AttachmentCache? attachmentCache;
  final OAuthService oauthService;
  final DateTime Function() _now;

  final Map<String, Future<OAuth2MailAuth>> _inFlightRefreshes = {};
  final Set<String> _reauthRequiredAccountIds = {};

  AccountRepository({
    required this.db,
    FlutterSecureStorage? storage,
    this.attachmentCache,
    OAuthService? oauthService,
    DateTime Function()? now,
  })  : secureStorage = storage ?? const FlutterSecureStorage(),
        oauthService = oauthService ?? OAuthService(),
        _now = now ?? DateTime.now;

  /// Returns true if [accountId] failed OAuth refresh and requires interactive re-authentication.
  bool isReauthRequired(String accountId) => _reauthRequiredAccountIds.contains(accountId);

  /// Clears the re-auth required flag for [accountId] (e.g. after successful re-auth).
  void clearReauthRequired(String accountId) => _reauthRequiredAccountIds.remove(accountId);

  /// Marks [accountId] as requiring re-auth.
  void markReauthRequired(String accountId) => _reauthRequiredAccountIds.add(accountId);

  Future<void> saveAccount(AccountRecord account, MailAuth auth) async {
    db.db.execute('''
      INSERT OR REPLACE INTO accounts
      (id, email, display_name, imap_host, imap_port, smtp_host, smtp_port, auth_type, created_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    ''', [
      account.id,
      account.email,
      account.displayName,
      account.imapHost,
      account.imapPort,
      account.smtpHost,
      account.smtpPort,
      account.authType,
      account.createdAt.toIso8601String(),
    ]);

    if (auth is PasswordMailAuth) {
      await secureStorage.write(key: 'auth_pass_${account.id}', value: auth.password);
    } else if (auth is OAuth2MailAuth) {
      await secureStorage.write(key: 'auth_oauth_token_${account.id}', value: auth.accessToken);
      if (auth.refreshToken != null) {
        await secureStorage.write(key: 'auth_oauth_refresh_${account.id}', value: auth.refreshToken);
      }
      if (auth.expiresAt != null) {
        await secureStorage.write(key: 'auth_oauth_expires_${account.id}', value: auth.expiresAt!.toIso8601String());
      } else {
        await secureStorage.delete(key: 'auth_oauth_expires_${account.id}');
      }
      await secureStorage.write(key: 'auth_oauth_provider_${account.id}', value: auth.provider.name);
      clearReauthRequired(account.id);
    }
  }

  Future<MailAuth?> getAuthForAccount(String accountId) async {
    final inFlight = _inFlightRefreshes[accountId];
    if (inFlight != null) {
      return await inFlight;
    }

    final pass = await secureStorage.read(key: 'auth_pass_$accountId');
    if (pass != null) {
      return PasswordMailAuth(pass);
    }

    final token = await secureStorage.read(key: 'auth_oauth_token_$accountId');
    if (token != null) {
      final refresh = await secureStorage.read(key: 'auth_oauth_refresh_$accountId');
      final expiresStr = await secureStorage.read(key: 'auth_oauth_expires_$accountId');
      final providerStr = await secureStorage.read(key: 'auth_oauth_provider_$accountId');

      DateTime? expiresAt;
      if (expiresStr != null) {
        expiresAt = DateTime.tryParse(expiresStr);
      }

      final now = _now();
      final needsRefresh = expiresAt == null || expiresAt.isBefore(now.add(const Duration(minutes: 2)));

      OAuthProvider provider = OAuthProvider.google;
      if (providerStr != null) {
        provider = OAuthProvider.values.where((p) => p.name == providerStr).firstOrNull ?? OAuthProvider.google;
      } else {
        try {
          final acc = getAccount(accountId);
          if (acc != null) {
            if (acc.authType == 'oauth_microsoft') {
              provider = OAuthProvider.microsoft;
            } else if (acc.authType == 'oauth_google') {
              provider = OAuthProvider.google;
            }
          }
        } catch (_) {}
      }

      if (!needsRefresh) {
        return OAuth2MailAuth(
          token,
          refreshToken: refresh,
          expiresAt: expiresAt,
          provider: provider,
        );
      }

      final inFlightAgain = _inFlightRefreshes[accountId];
      if (inFlightAgain != null) {
        return await inFlightAgain;
      }

      final future = _refreshOAuth(
        accountId: accountId,
        refreshToken: refresh,
        provider: provider,
      );
      _inFlightRefreshes[accountId] = future;
      try {
        return await future;
      } finally {
        _inFlightRefreshes.remove(accountId);
      }
    }

    return null;
  }

  Future<OAuth2MailAuth> _refreshOAuth({
    required String accountId,
    required String? refreshToken,
    required OAuthProvider provider,
  }) async {
    String email = '';
    try {
      final acc = getAccount(accountId);
      if (acc != null) {
        email = acc.email;
      }
    } catch (_) {}

    if (refreshToken == null || refreshToken.isEmpty) {
      markReauthRequired(accountId);
      throw ReauthRequiredException(
        accountId: accountId,
        email: email,
        provider: provider,
      );
    }

    try {
      final newTokens = await oauthService.refresh(
        provider: provider,
        refreshToken: refreshToken,
        accountId: accountId,
        email: email,
        flightKey: accountId,
      );

      await secureStorage.write(key: 'auth_oauth_token_$accountId', value: newTokens.accessToken);
      if (newTokens.refreshToken != null && newTokens.refreshToken!.isNotEmpty) {
        await secureStorage.write(key: 'auth_oauth_refresh_$accountId', value: newTokens.refreshToken!);
      }
      await secureStorage.write(key: 'auth_oauth_expires_$accountId', value: newTokens.expiresAt.toIso8601String());
      await secureStorage.write(key: 'auth_oauth_provider_$accountId', value: provider.name);
      clearReauthRequired(accountId);

      return OAuth2MailAuth(
        newTokens.accessToken,
        refreshToken: newTokens.refreshToken ?? refreshToken,
        expiresAt: newTokens.expiresAt,
        provider: provider,
      );
    } on ReauthRequiredException catch (e) {
      markReauthRequired(accountId);
      if (e.accountId.isEmpty || e.email.isEmpty) {
        throw ReauthRequiredException(
          accountId: accountId,
          email: email.isNotEmpty ? email : e.email,
          provider: provider,
        );
      }
      rethrow;
    } on DfOAuthInvalidGrantException {
      markReauthRequired(accountId);
      throw ReauthRequiredException(
        accountId: accountId,
        email: email,
        provider: provider,
      );
    }
  }

  AccountRecord? getAccount(String id) {
    final rows = db.db.select('SELECT * FROM accounts WHERE id = ?', [id]);
    if (rows.isEmpty) return null;
    final r = rows.first;
    return AccountRecord(
      id: r['id'] as String,
      email: r['email'] as String,
      displayName: r['display_name'] as String,
      imapHost: r['imap_host'] as String,
      imapPort: r['imap_port'] as int,
      smtpHost: r['smtp_host'] as String,
      smtpPort: r['smtp_port'] as int,
      authType: r['auth_type'] as String,
      createdAt: DateTime.parse(r['created_at'] as String),
    );
  }

  List<AccountRecord> listAccounts() {
    final rows = db.db.select('SELECT * FROM accounts ORDER BY created_at ASC');
    return rows.map((r) => AccountRecord(
      id: r['id'] as String,
      email: r['email'] as String,
      displayName: r['display_name'] as String,
      imapHost: r['imap_host'] as String,
      imapPort: r['imap_port'] as int,
      smtpHost: r['smtp_host'] as String,
      smtpPort: r['smtp_port'] as int,
      authType: r['auth_type'] as String,
      createdAt: DateTime.parse(r['created_at'] as String),
    )).toList();
  }

  Future<void> deleteAccount(String accountId) async {
    _inFlightRefreshes.remove(accountId);
    _reauthRequiredAccountIds.remove(accountId);
    // Local data first and synchronously, so the account is gone even if the
    // keychain call below is slow or hangs. The learned filter (tokens) stays.
    const ofAccount = 'SELECT id FROM messages WHERE account_id = ?';
    db.db.execute('DELETE FROM bodies WHERE message_id IN ($ofAccount)', [accountId]);
    db.db.execute('DELETE FROM classifications WHERE message_id IN ($ofAccount)', [accountId]);
    db.db.execute('DELETE FROM attachments WHERE message_id IN ($ofAccount)', [accountId]);
    db.db.execute('DELETE FROM messages WHERE account_id = ?', [accountId]);
    db.db.execute('DELETE FROM pending_imap_actions WHERE account_id = ?', [accountId]);
    db.db.execute('DELETE FROM folders WHERE account_id = ?', [accountId]);
    db.db.execute('DELETE FROM settings WHERE key = ?', ['uid_sync_v2_$accountId']);
    db.db.execute('DELETE FROM accounts WHERE id = ?', [accountId]);
    try {
      await attachmentCache?.deleteAccount(accountId);
    } catch (e, st) {
      logError('delete cached attachments', e, st); // must not keep the keychain entries alive
    }
    await secureStorage.delete(key: 'auth_pass_$accountId');
    await secureStorage.delete(key: 'auth_oauth_token_$accountId');
    await secureStorage.delete(key: 'auth_oauth_refresh_$accountId');
    await secureStorage.delete(key: 'auth_oauth_expires_$accountId');
    await secureStorage.delete(key: 'auth_oauth_provider_$accountId');
  }
}

final oauthServiceProvider = Provider<OAuthService>((ref) => OAuthService());

final attachmentCacheProvider = Provider<AttachmentCache>((ref) => AttachmentCache());

final accountRepositoryProvider = Provider<AccountRepository>((ref) {
  final db = ref.watch(databaseProvider);
  return AccountRepository(
    db: db,
    attachmentCache: ref.watch(attachmentCacheProvider),
    oauthService: ref.watch(oauthServiceProvider),
  );
});
