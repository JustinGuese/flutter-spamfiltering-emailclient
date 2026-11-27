import 'dart:async';
import 'contracts.dart';

/// In-memory implementation of TokenStore for testing, CLI, and caching.
class MemoryTokenStore implements TokenStore {
  final Map<int, TokenCounts> _counts;
  int _totalSpam;
  int _totalHam;

  MemoryTokenStore([
    Map<int, TokenCounts>? initial,
    int totalSpam = 0,
    int totalHam = 0,
  ])  : _counts = initial != null ? Map.of(initial) : {},
        _totalSpam = totalSpam,
        _totalHam = totalHam;

  @override
  Future<({int spam, int ham})> messageTotals() async {
    return (spam: _totalSpam, ham: _totalHam);
  }

  /// Adjusts class totals for trained messages.
  void addMessages(Label label, int delta) {
    switch (label) {
      case Label.spam:
        _totalSpam = (_totalSpam + delta).clamp(0, 1000000000);
        break;
      case Label.ham:
      case Label.newsletter:
      case Label.inbox:
        _totalHam = (_totalHam + delta).clamp(0, 1000000000);
        break;
    }
  }

  @override
  FutureOr<TokenCounts> counts(int hash) {
    return _counts[hash] ?? const TokenCounts();
  }

  @override
  FutureOr<void> apply(int hash, Label label, int delta) {
    final current = _counts[hash] ?? const TokenCounts();
    TokenCounts updated;

    switch (label) {
      case Label.spam:
        updated = current.copyWith(spam: (current.spam + delta).clamp(0, 1000000));
        break;
      case Label.ham:
        updated = current.copyWith(ham: (current.ham + delta).clamp(0, 1000000));
        break;
      case Label.newsletter:
        updated = current.copyWith(newsletter: (current.newsletter + delta).clamp(0, 1000000));
        break;
      case Label.inbox:
        updated = current.copyWith(inbox: (current.inbox + delta).clamp(0, 1000000));
        break;
    }

    _counts[hash] = updated;
  }

  /// Exposes the underlying map for serialization.
  Map<int, TokenCounts> get allCounts => Map.unmodifiable(_counts);

  /// Number of tokens in the store.
  int get size => _counts.length;

  /// Clear all stored tokens.
  void clear() => _counts.clear();
}

/// Compatibility alias.
typedef InMemoryTokenStore = MemoryTokenStore;
