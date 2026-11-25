import 'package:spam_core/spam_core.dart';
import '../db/database.dart';
import 'token_store_drift.dart';

/// Bootstraps local learning from existing Junk folders and Sent recipients.
class ColdStartTrainer {
  final AppDatabase db;
  final TokenStoreDrift tokenStore;

  ColdStartTrainer({
    required this.db,
    required this.tokenStore,
  });

  Future<void> runColdStart() async {
    // 1. Seed prior model from assets if tokens are empty
    await tokenStore.seedPriorModelIfEmpty();

    // 2. Train spam from messages in Junk folders. Runs once: counts are
    // incremental, so repeating it every launch inflated the spam counts, and
    // as autocommits (one disk sync per token) it blocked the first frame.
    if (db.getSetting(_junkTrainedKey) != '1') {
      _trainFromJunk();
    }

    // 3. Populate contacts from Sent folder to trust them as ham
    final sentRows = db.db.select('''
      SELECT DISTINCT m.recipient_addrs
      FROM messages m
      JOIN folders f ON m.folder_id = f.id
      WHERE f.special_use = 'sent'
    ''');

    db.db.execute('BEGIN');
    try {
      for (final row in sentRows) {
        final addrs = ((row['recipient_addrs'] as String?) ?? '')
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.contains('@'));

        for (final addr in addrs) {
          db.db.execute('''
            INSERT OR REPLACE INTO contacts (id, email, trust_level, always_allow_images)
            VALUES (?, ?, 1, 1)
          ''', [addr.toLowerCase(), addr.toLowerCase()]);
        }
      }
      db.db.execute('COMMIT');
    } catch (_) {
      db.db.execute('ROLLBACK');
      rethrow;
    }
  }

  static const _junkTrainedKey = 'cold_start_junk_trained';

  /// Trains every Junk message into the token counts in ONE transaction and
  /// records that it did, so a later launch skips it.
  void _trainFromJunk() {
    final junkRows = db.db.select('''
      SELECT m.id, m.subject, m.sender, m.recipient_addrs, b.text_body, b.html_body
      FROM messages m
      JOIN folders f ON m.folder_id = f.id
      LEFT JOIN bodies b ON m.id = b.message_id
      WHERE f.special_use = 'junk'
    ''');

    db.db.execute('BEGIN');
    try {
      for (final row in junkRows) {
        final msg = Message(
          headers: {
            'From': [row['sender'] as String],
            'Subject': [row['subject'] as String],
          },
          textBody: (row['text_body'] as String?) ?? '',
          htmlBody: row['html_body'] as String?,
          recipientAddrs: ((row['recipient_addrs'] as String?) ?? '')
              .split(',')
              .map((s) => s.trim())
              .toList(),
        );
        final tokens = Tokenizer.tokens(Normalizer.normalize(msg));
        for (final t in tokens) {
          tokenStore.apply(Tokenizer.hashToken(t), Label.spam, 1);
        }
      }
      db.setSetting(_junkTrainedKey, '1');
      db.db.execute('COMMIT');
    } catch (_) {
      db.db.execute('ROLLBACK');
      rethrow;
    }
  }
}
