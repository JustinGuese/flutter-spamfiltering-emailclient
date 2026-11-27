import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqlite3/sqlite3.dart' show Database;
import '../db/database.dart';
import '../mail/sync_engine.dart';

/// Where clause and arguments for SQL queries.
class WhereClause {
  final String sql;
  final List<Object?> args;
  const WhereClause(this.sql, [this.args = const []]);
}

/// Service managing the New Senders screener and review queries.
class Screener {
  final AppDatabase appDb;

  Screener(this.appDb);

  Database get db => appDb.db;

  /// Gets the current screener mode ('tab' default or 'strict').
  String getScreenerMode() {
    final rows = db.select("SELECT value FROM settings WHERE key = 'screener_mode'");
    if (rows.isNotEmpty) {
      return rows.first['value'] as String;
    }
    return 'tab';
  }

  /// Sets the screener mode ('tab' or 'strict').
  void setScreenerMode(String mode) {
    db.execute(
      "INSERT INTO settings (key, value) VALUES ('screener_mode', ?) "
      "ON CONFLICT(key) DO UPDATE SET value = excluded.value",
      [mode],
    );
  }

  /// Helper generating SQLite expression to extract lowercased email from sender string.
  static String senderEmailExpr(String alias) =>
      "CASE WHEN INSTR($alias.sender, '<') > 0 "
      "THEN LOWER(RTRIM(SUBSTR($alias.sender, INSTR($alias.sender, '<') + 1), '>')) "
      "ELSE LOWER(TRIM($alias.sender)) END";

  /// Generates the WHERE clause matching messages from new senders in Inbox.
  ///
  /// Criteria:
  /// - In Inbox folder
  /// - Sender address is NOT in contacts
  /// - Sender has NO allow rule in sender_rules (neither address nor domain rule)
  /// - No OTHER message from the same sender in the account outside Junk/Trash is older than this one.
  WhereClause newSenderWhereClause({String tableAlias = 'messages'}) {
    final a = tableAlias;

    final sql = '''
($a.folder_id IN (SELECT id FROM folders WHERE LOWER(COALESCE(special_use, '')) = 'inbox' OR LOWER(name) = 'inbox')
AND NOT EXISTS (
  SELECT 1 FROM contacts c
  WHERE c.email = $a.sender_email
)
AND NOT EXISTS (
  SELECT 1 FROM sender_rules sr
  WHERE sr.action = 'allow'
    AND (
      (sr.kind = 'address' AND sr.pattern = $a.sender_email)
      OR (sr.kind = 'domain' AND (
        $a.sender_email LIKE '%@' || sr.pattern
        OR $a.sender_email LIKE '%.' || sr.pattern
        OR LOWER(TRIM(COALESCE($a.sender_domain, ''))) = sr.pattern
      ))
    )
)
AND NOT EXISTS (
  SELECT 1 FROM messages o
  JOIN folders ofld ON o.folder_id = ofld.id
  WHERE o.id != $a.id
    AND o.account_id = $a.account_id
    AND LOWER(COALESCE(ofld.special_use, '')) NOT IN ('junk', 'trash')
    AND o.sender_email = $a.sender_email
    AND (o.date < $a.date OR (o.date = $a.date AND o.id < $a.id))
))''';

    return WhereClause(sql, const []);
  }

  /// Checks whether a given message is from a new sender.
  bool isNewSender(String msgId) {
    final where = newSenderWhereClause(tableAlias: 'm');
    final rows = db.select('''
      SELECT 1 FROM messages m
      WHERE m.id = ? AND ${where.sql}
    ''', [msgId, ...where.args]);
    return rows.isNotEmpty;
  }
}

final screenerProvider = Provider<Screener>((ref) {
  final db = ref.watch(databaseProvider);
  return Screener(db);
});

final screenerModeProvider = Provider<String>((ref) {
  ref.watch(mailRevisionProvider);
  final screener = ref.watch(screenerProvider);
  return screener.getScreenerMode();
});
