import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spam_core/spam_core.dart';
import '../db/database.dart';
import '../app/log.dart';

/// Drift-backed implementation of [TokenStore] storing token counts in SQLite.
class TokenStoreDrift implements TokenStore {
  final AppDatabase db;

  TokenStoreDrift(this.db);

  @override
  TokenCounts counts(int hash) {
    final rows = db.db.select(
      'SELECT spam, ham, newsletter, inbox FROM tokens WHERE hash = ?',
      [hash],
    );
    if (rows.isEmpty) {
      return const TokenCounts();
    }
    final r = rows.first;
    return TokenCounts(
      spam: r['spam'] as int,
      ham: r['ham'] as int,
      newsletter: r['newsletter'] as int,
      inbox: r['inbox'] as int,
    );
  }

  @override
  void apply(int hash, Label label, int delta) {
    final col = switch (label) {
      Label.spam => 'spam',
      Label.ham => 'ham',
      Label.newsletter => 'newsletter',
      Label.inbox => 'inbox',
    };

    final current = counts(hash);
    final nextSpam = label == Label.spam ? (current.spam + delta).clamp(0, 1000000) : current.spam;
    final nextHam = label == Label.ham ? (current.ham + delta).clamp(0, 1000000) : current.ham;
    final nextNews = label == Label.newsletter ? (current.newsletter + delta).clamp(0, 1000000) : current.newsletter;
    final nextInbox = label == Label.inbox ? (current.inbox + delta).clamp(0, 1000000) : current.inbox;

    db.db.execute('''
      INSERT INTO tokens (hash, spam, ham, newsletter, inbox)
      VALUES (?, ?, ?, ?, ?)
      ON CONFLICT(hash) DO UPDATE SET $col = MAX(0, $col + ?)
    ''', [hash, nextSpam, nextHam, nextNews, nextInbox, delta]);
  }

  /// Ingests the initial static prior model asset if tokens table is empty.
  Future<void> seedPriorModelIfEmpty() async {
    final countRow = db.db.select('SELECT COUNT(*) as cnt FROM tokens');
    final count = (countRow.firstOrNull?['cnt'] as int?) ?? 0;
    if (count > 0) return;

    try {
      final jsonStr = await rootBundle.loadString('assets/prior_model.json');
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;
      final totalSpam = (data['total_spam'] as num?)?.toInt() ?? 0;
      final totalHam = (data['total_ham'] as num?)?.toInt() ?? 0;
      final tokensMap = data['tokens'] as Map<String, dynamic>? ?? {};

      db.db.execute('BEGIN TRANSACTION');
      for (final entry in tokensMap.entries) {
        final token = entry.key;
        final hash = int.tryParse(token) ?? Tokenizer.hashToken(token);
        final counts = entry.value as Map<String, dynamic>;
        final spam = (counts['spam'] as num?)?.toInt() ?? 0;
        final ham = (counts['ham'] as num?)?.toInt() ?? 0;

        db.db.execute('''
          INSERT OR REPLACE INTO tokens (hash, spam, ham, newsletter, inbox)
          VALUES (?, ?, ?, 0, 0)
        ''', [hash, spam, ham]);
        // Baseline every device seeds identically: filter sync never uploads it
        // and the "words learned" figure does not count it.
        db.db.execute(
          'INSERT OR REPLACE INTO prior_tokens (hash, spam, ham) VALUES (?, ?, ?)',
          [hash, spam, ham],
        );
      }
      if (totalSpam > 0) db.setSetting('msg_total_spam', totalSpam.toString());
      if (totalHam > 0) db.setSetting('msg_total_ham', totalHam.toString());
      db.db.execute('COMMIT');
    } catch (e, st) {
      logError('token store', e, st);
      try {
        db.db.execute('ROLLBACK');
      } catch (e2, st2) {
        logError('token store rollback', e2, st2);
      }
    }
  }

  int totalTrainedTokens() {
    final row = db.db.select('SELECT SUM(spam + ham + newsletter + inbox) as total FROM tokens');
    return (row.firstOrNull?['total'] as int?) ?? 0;
  }

  @override
  Future<({int spam, int ham})> messageTotals() async {
    final spam = int.tryParse(db.getSetting('msg_total_spam') ?? '') ?? 0;
    final ham = int.tryParse(db.getSetting('msg_total_ham') ?? '') ?? 0;
    return (spam: spam, ham: ham);
  }

  /// Hashes of the two tokens the tokenizer emits for every message, exactly
  /// one of them per message (`list-unsub:absent` / `list-unsub:present`).
  static final List<int> _perMessageTokens = [
    Tokenizer.hashToken('list-unsub:absent'),
    Tokenizer.hashToken('list-unsub:present'),
  ];

  /// Raises the stored message totals to at least the number of messages the
  /// token counts prove were trained, never lowers them.
  ///
  /// Totals are newer than token training: installs that trained before they
  /// existed have counts but no totals, and filter sync merges remote counts
  /// without totals. Each tokenized message adds exactly one per-message
  /// token, so their summed counts are the trained message count per class.
  /// The hand-made seed prior has no such tokens, so it never inflates this.
  void reconcileMessageTotals() {
    final placeholders = _perMessageTokens.map((_) => '?').join(', ');
    final row = db.db.select(
      'SELECT COALESCE(SUM(spam), 0) AS s, COALESCE(SUM(ham), 0) AS h '
      'FROM tokens WHERE hash IN ($placeholders)',
      _perMessageTokens,
    ).first;
    void raise(String key, int estimate) {
      final current = int.tryParse(db.getSetting(key) ?? '') ?? 0;
      if (estimate > current) db.setSetting(key, estimate.toString());
    }
    raise('msg_total_spam', (row['s'] as num).toInt());
    raise('msg_total_ham', (row['h'] as num).toInt());
  }

  void addMessages(Label label, int delta) {
    final key = label == Label.spam ? 'msg_total_spam' : 'msg_total_ham';
    final current = int.tryParse(db.getSetting(key) ?? '') ?? 0;
    final updated = (current + delta).clamp(0, 1000000000);
    db.setSetting(key, updated.toString());
  }
}

final tokenStoreProvider = Provider<TokenStoreDrift>((ref) {
  final db = ref.watch(databaseProvider);
  return TokenStoreDrift(db);
});
