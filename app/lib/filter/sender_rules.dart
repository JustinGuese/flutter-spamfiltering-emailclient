import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spam_core/spam_core.dart';
import '../db/database.dart';

/// A configured rule allowing or blocking a sender address or domain.
class SenderRule {
  final String pattern;
  final String kind; // 'address' | 'domain'
  final SenderRuleAction action;
  final DateTime createdAt;

  const SenderRule({
    required this.pattern,
    required this.kind,
    required this.action,
    required this.createdAt,
  });
}

/// Evaluates and manages sender and domain rules and contact trust.
class SenderRules {
  final AppDatabase db;

  SenderRules(this.db);

  /// Normalizes an email address or string with optional display name.
  static String extractEmail(String input) {
    final trimmed = input.trim();
    final match = RegExp(r'<([^>]+)>').firstMatch(trimmed);
    if (match != null) {
      return match.group(1)!.trim().toLowerCase();
    }
    return trimmed.toLowerCase();
  }

  /// Normalizes pattern according to rule kind.
  static String cleanPattern(String pattern, String kind) {
    var p = pattern.trim().toLowerCase();
    if (kind == 'domain') {
      if (p.startsWith('@')) p = p.substring(1);
      if (p.startsWith('.')) p = p.substring(1);
    } else {
      final match = RegExp(r'<([^>]+)>').firstMatch(p);
      if (match != null) p = match.group(1)!.trim();
    }
    return p;
  }

  /// Looks up rule for a sender address.
  /// Lowercases; address rule beats domain rule; domain rule matches exact domain and subdomains.
  SenderRuleAction? lookup(String senderAddress) {
    final addr = extractEmail(senderAddress);

    // 1. Address rule takes precedence.
    final addrRow = db.db.select(
      "SELECT action FROM sender_rules WHERE kind = 'address' AND pattern = ?",
      [addr],
    );
    if (addrRow.isNotEmpty) {
      return _parseAction(addrRow.first['action'] as String);
    }

    // 2. Domain rule matches exact domain or parent subdomains.
    final domain = addr.contains('@') ? addr.split('@').last.trim() : addr;
    final parts = domain.split('.');
    for (var i = 0; i < parts.length - 1; i++) {
      final candidate = parts.sublist(i).join('.');
      final row = db.db.select(
        "SELECT action FROM sender_rules WHERE kind = 'domain' AND pattern = ?",
        [candidate],
      );
      if (row.isNotEmpty) {
        return _parseAction(row.first['action'] as String);
      }
    }

    return null;
  }

  /// Sets an allow or block rule for [pattern] (address or domain).
  void set(String pattern, String kind, SenderRuleAction action) {
    final cleaned = cleanPattern(pattern, kind);
    final now = DateTime.now().toUtc().toIso8601String();
    db.db.execute('''
      INSERT OR REPLACE INTO sender_rules (pattern, kind, action, created_at)
      VALUES (?, ?, ?, ?)
    ''', [cleaned, kind, action.name, now]);
  }

  /// Removes any rule with [pattern].
  void remove(String pattern) {
    final cleaned = pattern.trim().toLowerCase();
    var alt = cleaned;
    if (alt.startsWith('@')) alt = alt.substring(1);
    if (alt.startsWith('.')) alt = alt.substring(1);
    db.db.execute(
      'DELETE FROM sender_rules WHERE pattern = ? OR pattern = ?',
      [cleaned, alt],
    );
  }

  /// Returns all configured sender rules, newest first.
  List<SenderRule> all() {
    final rows = db.db.select(
      'SELECT pattern, kind, action, created_at FROM sender_rules ORDER BY created_at DESC',
    );
    return rows.map((r) => SenderRule(
      pattern: r['pattern'] as String,
      kind: r['kind'] as String,
      action: _parseAction(r['action'] as String),
      createdAt: DateTime.tryParse(r['created_at'] as String) ?? DateTime.now(),
    )).toList();
  }

  /// Checks if [address] belongs to a contact with trust_level >= 1.
  bool isContact(String address) {
    final addr = extractEmail(address);
    final rows = db.db.select(
      'SELECT 1 FROM contacts WHERE LOWER(TRIM(email)) = ? AND trust_level >= 1',
      [addr],
    );
    return rows.isNotEmpty;
  }

  static SenderRuleAction _parseAction(String value) {
    return value.toLowerCase() == 'allow' ? SenderRuleAction.allow : SenderRuleAction.block;
  }
}

final senderRulesProvider = Provider<SenderRules>((ref) {
  final db = ref.watch(databaseProvider);
  return SenderRules(db);
});
