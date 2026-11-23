import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Database management backed by SQLite (matching Drift C3 schema in tables.dart).
class AppDatabase {
  final Database db;

  AppDatabase(this.db) {
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
        spam_score REAL NOT NULL DEFAULT 0.0
      );
      CREATE TABLE IF NOT EXISTS bodies (
        message_id TEXT PRIMARY KEY,
        text_body TEXT,
        html_body TEXT,
        sanitized_html TEXT,
        remote_images_blocked INTEGER NOT NULL DEFAULT 1
      );
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
    ''');
    _migrate();
  }

  /// There is no schema version: each step checks the live table and adds only
  /// what is missing, so it is safe on fresh and existing databases alike.
  void _migrate() {
    final messageCols = db.select('PRAGMA table_info(messages)').map((r) => r['name']).toSet();
    if (!messageCols.contains('cc_addrs')) {
      // Mail synced before this column existed keeps '' until it is re-fetched.
      db.execute("ALTER TABLE messages ADD COLUMN cc_addrs TEXT NOT NULL DEFAULT ''");
    }
  }

  void close() => db.close();
}

final databaseProvider = Provider<AppDatabase>((ref) {
  throw UnimplementedError('databaseProvider must be overridden at startup');
});
