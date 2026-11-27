import 'dart:math' as math;
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
    tokenStore.reconcileMessageTotals();

    // 2. Train spam from messages in Junk folders. Runs once: counts are
    // incremental, so repeating it every launch inflated the spam counts, and
    // as autocommits (one disk sync per token) it blocked the first frame.
    int junkCount = 0;
    if (db.getSetting(_junkTrainedKey) != '1') {
      junkCount = _trainFromJunk();
    } else {
      final junkRow = db.db.select('''
        SELECT COUNT(*) as cnt
        FROM messages m
        JOIN folders f ON m.folder_id = f.id
        WHERE f.special_use = 'junk'
      ''');
      junkCount = (junkRow.firstOrNull?['cnt'] as int?) ?? 0;
    }

    // 3. Train ham from inbox/user folders. Runs once.
    if (db.getSetting(_hamTrainedKey) != '1') {
      _trainHam(junkCount);
    }

    // 4. Populate contacts from Sent folder to trust them as ham
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
            INSERT INTO contacts (id, email, trust_level, always_allow_images)
            VALUES (?, ?, 1, 1)
            ON CONFLICT(id) DO UPDATE SET trust_level = MAX(trust_level, 1)
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
  static const _hamTrainedKey = 'cold_start_ham_trained';

  /// Fewest read Inbox messages worth training as ham; below this, wait.
  static const minHamMessages = 20;

  /// Trains every Junk message into the token counts in ONE transaction and
  /// records that it did, so a later launch skips it.
  int _trainFromJunk() {
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
      tokenStore.addMessages(Label.spam, junkRows.length);
      db.setSetting(_junkTrainedKey, '1');
      db.db.execute('COMMIT');
      return junkRows.length;
    } catch (_) {
      db.db.execute('ROLLBACK');
      rethrow;
    }
  }

  /// Trains ham messages from Inbox/user folders into the token counts in ONE transaction.
  void _trainHam(int junkCount) {
    final limit = math.min(500, math.max(50, junkCount));
    final hamRows = db.db.select('''
      SELECT m.id, m.subject, m.sender, m.recipient_addrs, b.text_body, b.html_body
      FROM messages m
      JOIN folders f ON m.folder_id = f.id
      LEFT JOIN bodies b ON m.id = b.message_id
      WHERE (f.special_use = 'inbox' OR f.special_use IS NULL)
        AND COALESCE(f.special_use, '') != 'sent'
        AND m.is_read = 1
        AND m.spam_score < 0.6
        AND NOT EXISTS (
          SELECT 1 FROM classifications c
          WHERE c.message_id = m.id AND c.user_overridden = 1 AND c.label = 'spam'
        )
      ORDER BY m.date DESC
      LIMIT ?
    ''', [limit]);

    // A fresh install runs this at launch, before the first sync, on an empty
    // mailbox. Train only once there is enough read mail and only then set the
    // flag, so the run after the first sync (AppBootstrap) does the training.
    if (hamRows.length < minHamMessages) return;

    db.db.execute('BEGIN');
    try {
      for (final row in hamRows) {
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
          tokenStore.apply(Tokenizer.hashToken(t), Label.ham, 1);
        }
      }
      tokenStore.addMessages(Label.ham, hamRows.length);
      db.setSetting(_hamTrainedKey, '1');
      db.db.execute('COMMIT');
    } catch (_) {
      db.db.execute('ROLLBACK');
      rethrow;
    }
  }
}
