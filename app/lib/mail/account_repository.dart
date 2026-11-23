import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../app/log.dart';
import '../db/database.dart';
import 'attachments.dart';
import 'mail_auth.dart';

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

  AccountRepository({
    required this.db,
    FlutterSecureStorage? storage,
    this.attachmentCache,
  }) : secureStorage = storage ?? const FlutterSecureStorage();

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
    }
  }

  Future<MailAuth?> getAuthForAccount(String accountId) async {
    final pass = await secureStorage.read(key: 'auth_pass_$accountId');
    if (pass != null) {
      return PasswordMailAuth(pass);
    }
    final token = await secureStorage.read(key: 'auth_oauth_token_$accountId');
    if (token != null) {
      final refresh = await secureStorage.read(key: 'auth_oauth_refresh_$accountId');
      return OAuth2MailAuth(token, refreshToken: refresh);
    }
    return null;
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
  }
}

final attachmentCacheProvider = Provider<AttachmentCache>((ref) => AttachmentCache());

final accountRepositoryProvider = Provider<AccountRepository>((ref) {
  final db = ref.watch(databaseProvider);
  return AccountRepository(db: db, attachmentCache: ref.watch(attachmentCacheProvider));
});
