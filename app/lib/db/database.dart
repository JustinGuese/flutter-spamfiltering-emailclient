import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Database management backed by SQLite (matching Drift C3 schema in tables.dart).
class AppDatabase {
  final Database db;

  AppDatabase(this.db) {
    // Needed so INSERT OR REPLACE on `bodies` fires the DELETE trigger that
    // keeps the search index in step (SQLite skips it by default).
    db.execute('PRAGMA recursive_triggers = ON');
    _createTables();
  }

  static Future<AppDatabase> open({bool inMemory = false}) async {
    if (inMemory) {
      return AppDatabase(sqlite3.openInMemory());
    }
    final dir = await getApplicationDocumentsDirectory();
    final dbFile = File(p.join(dir.path, 'datafortress_mail.db'));
    return AppDatabase(sqlite3.open(dbFile.path));
  }

  void _createTables() {
    db.execute('''
      CREATE TABLE IF NOT EXISTS accounts (
        id TEXT PRIMARY KEY,
        email TEXT NOT NULL,
        display_name TEXT NOT NULL,
        imap_host TEXT NOT NULL,
        imap_port INTEGER NOT NULL,
        smtp_host TEXT NOT NULL,
        smtp_port INTEGER NOT NULL,
        auth_type TEXT NOT NULL DEFAULT 'password',
        created_at TEXT NOT NULL
      );
      CREATE TABLE IF NOT EXISTS folders (
        id TEXT PRIMARY KEY,
        account_id TEXT NOT NULL,
        name TEXT NOT NULL,
        server_path TEXT NOT NULL,
        special_use TEXT,
        uid_validity INTEGER,
        last_seen_uid INTEGER,
        unread_count INTEGER NOT NULL DEFAULT 0
      );
      CREATE TABLE IF NOT EXISTS messages (
        id TEXT PRIMARY KEY,
        account_id TEXT NOT NULL,
        folder_id TEXT NOT NULL,
        uid INTEGER NOT NULL,
        message_id TEXT,
        subject TEXT NOT NULL,
        sender TEXT NOT NULL,
        sender_domain TEXT,
        recipient_addrs TEXT NOT NULL,
        cc_addrs TEXT NOT NULL DEFAULT '',
        date TEXT NOT NULL,
        snippet TEXT NOT NULL,
        is_read INTEGER NOT NULL DEFAULT 0,
        is_flagged INTEGER NOT NULL DEFAULT 0,
        has_attachments INTEGER NOT NULL DEFAULT 0,
        classification_label TEXT NOT NULL DEFAULT 'inbox',
        spam_score REAL NOT NULL DEFAULT 0.0,
        list_unsubscribe TEXT,
        list_unsubscribe_post TEXT,
        sender_auth_pass INTEGER NOT NULL DEFAULT 0
      );
      CREATE TABLE IF NOT EXISTS bodies (
        message_id TEXT PRIMARY KEY,
        text_body TEXT,
        html_body TEXT,
        sanitized_html TEXT,
        remote_images_blocked INTEGER NOT NULL DEFAULT 1
      );
      CREATE TABLE IF NOT EXISTS attachments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        message_id TEXT NOT NULL,
        fetch_id TEXT NOT NULL,
        filename TEXT NOT NULL,
        mime_type TEXT NOT NULL,
        size INTEGER NOT NULL DEFAULT 0
      );
      CREATE INDEX IF NOT EXISTS attachments_message ON attachments (message_id);
      CREATE TABLE IF NOT EXISTS contacts (
        id TEXT PRIMARY KEY,
        email TEXT NOT NULL,
        name TEXT,
        trust_level INTEGER NOT NULL DEFAULT 0,
        always_allow_images INTEGER NOT NULL DEFAULT 0
      );
      CREATE TABLE IF NOT EXISTS classifications (
        message_id TEXT PRIMARY KEY,
        label TEXT NOT NULL,
        spam_score REAL NOT NULL,
        evidence_json TEXT NOT NULL,
        classified_at TEXT NOT NULL,
        user_overridden INTEGER NOT NULL DEFAULT 0
      );
      CREATE TABLE IF NOT EXISTS tokens (
        hash INTEGER PRIMARY KEY,
        spam INTEGER NOT NULL DEFAULT 0,
        ham INTEGER NOT NULL DEFAULT 0,
        newsletter INTEGER NOT NULL DEFAULT 0,
        inbox INTEGER NOT NULL DEFAULT 0
      );
      CREATE TABLE IF NOT EXISTS blocklist_entries (
        id TEXT PRIMARY KEY,
        type TEXT NOT NULL,
        hash_value INTEGER NOT NULL,
        added_at TEXT NOT NULL,
        expires_at TEXT
      );
      CREATE TABLE IF NOT EXISTS settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      );
      CREATE TABLE IF NOT EXISTS pending_imap_actions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        account_id TEXT NOT NULL,
        message_id TEXT NOT NULL,
        uid INTEGER NOT NULL,
        folder_id TEXT NOT NULL,
        action TEXT NOT NULL,
        target_folder TEXT
      );
      CREATE TABLE IF NOT EXISTS unsubscribe_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        account_id TEXT NOT NULL,
        sender_domain TEXT NOT NULL,
        message_id TEXT,
        method TEXT,
        status TEXT NOT NULL,
        created_at TEXT NOT NULL
      );
      CREATE INDEX IF NOT EXISTS idx_unsubscribe_log_account_sender
        ON unsubscribe_log (account_id, sender_domain);
    ''');
    _migrate();
    _createSearchIndex();
  }

  /// Full-text index for the Search tab. Its rowid is the rowid of the matching
  /// `bodies` row; triggers keep it current, so no write path has to know it
  /// exists. Everything stays on the device.
  void _createSearchIndex() {
    final existed = db.select("SELECT 1 FROM sqlite_master WHERE name = 'search_index'").isNotEmpty;
    db.execute('''
      CREATE VIRTUAL TABLE IF NOT EXISTS search_index USING fts5(
        subject, sender, recipients, body,
        tokenize = 'unicode61 remove_diacritics 2'
      );
      CREATE TRIGGER IF NOT EXISTS search_index_ai AFTER INSERT ON bodies BEGIN
        INSERT INTO search_index (rowid, subject, sender, recipients, body)
        SELECT new.rowid, m.subject, m.sender, m.recipient_addrs || ' ' || m.cc_addrs, COALESCE(new.text_body, '')
        FROM messages m WHERE m.id = new.message_id;
      END;
      CREATE TRIGGER IF NOT EXISTS search_index_au AFTER UPDATE ON bodies BEGIN
        DELETE FROM search_index WHERE rowid = old.rowid;
        INSERT INTO search_index (rowid, subject, sender, recipients, body)
        SELECT new.rowid, m.subject, m.sender, m.recipient_addrs || ' ' || m.cc_addrs, COALESCE(new.text_body, '')
        FROM messages m WHERE m.id = new.message_id;
      END;
      CREATE TRIGGER IF NOT EXISTS search_index_ad AFTER DELETE ON bodies BEGIN
        DELETE FROM search_index WHERE rowid = old.rowid;
      END;
    ''');
    if (!existed) {
      // Mail synced before the index existed.
      db.execute('''
        INSERT INTO search_index (rowid, subject, sender, recipients, body)
        SELECT b.rowid, m.subject, m.sender, m.recipient_addrs || ' ' || m.cc_addrs, COALESCE(b.text_body, '')
        FROM bodies b JOIN messages m ON m.id = b.message_id
      ''');
    }
  }

  /// There is no schema version: each step checks the live table and adds only
  /// what is missing, so it is safe on fresh and existing databases alike.
  void _migrate() {
    final messageCols = db.select('PRAGMA table_info(messages)').map((r) => r['name']).toSet();
    if (!messageCols.contains('cc_addrs')) {
      // Mail synced before this column existed keeps '' until it is re-fetched.
      db.execute("ALTER TABLE messages ADD COLUMN cc_addrs TEXT NOT NULL DEFAULT ''");
    }
    if (!messageCols.contains('list_unsubscribe')) {
      db.execute('ALTER TABLE messages ADD COLUMN list_unsubscribe TEXT');
    }
    if (!messageCols.contains('list_unsubscribe_post')) {
      db.execute('ALTER TABLE messages ADD COLUMN list_unsubscribe_post TEXT');
    }
    if (!messageCols.contains('sender_auth_pass')) {
      db.execute('ALTER TABLE messages ADD COLUMN sender_auth_pass INTEGER NOT NULL DEFAULT 0');
    }

    db.execute('''
      CREATE TABLE IF NOT EXISTS unsubscribe_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        account_id TEXT NOT NULL,
        sender_domain TEXT NOT NULL,
        message_id TEXT,
        method TEXT,
        status TEXT NOT NULL,
        created_at TEXT NOT NULL
      );
      CREATE INDEX IF NOT EXISTS idx_unsubscribe_log_account_sender
        ON unsubscribe_log (account_id, sender_domain);
    ''');
  }

  /// Returns the value for setting [key], or null if absent.
  String? getSetting(String key) {
    final rows = db.select('SELECT value FROM settings WHERE key = ?', [key]);
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  /// Sets the value for setting [key].
  void setSetting(String key, String value) {
    db.execute('INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)', [key, value]);
  }

  /// Whether auto-unsubscribe on spam verdict is enabled.
  /// Defaults to true when absent.
  bool get isAutoUnsubscribeEnabled {
    final val = getSetting('auto_unsubscribe');
    if (val == null) return true;
    return val.toLowerCase() != 'false' && val != '0';
  }

  void close() => db.close();
}

final databaseProvider = Provider<AppDatabase>((ref) {
  throw UnimplementedError('databaseProvider must be overridden at startup');
});
