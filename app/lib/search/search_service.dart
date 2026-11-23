import 'package:spam_core/spam_core.dart' show Label;
import 'package:sqlite3/sqlite3.dart' show SqliteException;
import '../db/database.dart';
import '../ui/mailbox/message_row.dart';
import 'search_query.dart';

/// Searches the on-device FTS5 index (`search_index`, see `database.dart`).
/// Ranking is BM25 with subject > sender > recipients > body; ties go to the
/// newer message. Spam is left out unless asked for.
List<MessageSummary> searchMessages(
  AppDatabase db,
  String input, {
  bool includeSpam = false,
  int limit = 100,
}) {
  final q = parseSearch(input);
  if (q.isEmpty) return const [];

  final where = [...q.where];
  final args = <Object?>[];
  if (q.match != null) args.add(q.match);
  args.addAll(q.args);
  if (!includeSpam && !q.wantsSpam) where.add("m.classification_label != 'spam'");
  final filters = where.isEmpty ? '' : (q.match != null ? 'AND ' : 'WHERE ') + where.join(' AND ');

  final sql = q.match != null
      ? '''
        SELECT m.*, snippet(search_index, 3, '', '', '…', 16) AS hit
        FROM search_index
        JOIN bodies b ON b.rowid = search_index.rowid
        JOIN messages m ON m.id = b.message_id
        WHERE search_index MATCH ? $filters
        ORDER BY bm25(search_index, 8.0, 4.0, 2.0, 1.0), m.date DESC
        LIMIT ?
      '''
      : '''
        SELECT m.*, NULL AS hit FROM messages m $filters
        ORDER BY m.date DESC LIMIT ?
      ''';

  try {
    return db.db.select(sql, [...args, limit]).map((r) {
      final hit = (r['hit'] as String?)?.replaceAll(RegExp(r'\s+'), ' ').trim();
      return MessageSummary(
        id: r['id'] as String,
        sender: r['sender'] as String,
        senderDomain: r['sender_domain'] as String?,
        subject: r['subject'] as String,
        snippet: (hit == null || hit.isEmpty) ? r['snippet'] as String : hit,
        date: DateTime.parse(r['date'] as String),
        isRead: (r['is_read'] as int) == 1,
        isFlagged: (r['is_flagged'] as int) == 1,
        hasAttachments: (r['has_attachments'] as int) == 1,
        label: Label.values.byName((r['classification_label'] as String?) ?? 'inbox'),
        spamScore: (r['spam_score'] as num?)?.toDouble() ?? 0.0,
      );
    }).toList();
  } on SqliteException {
    return const [];
  }
}
