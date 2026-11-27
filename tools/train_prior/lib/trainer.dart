import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:spam_core/spam_core.dart';

/// Scored token candidate for feature selection ranking.
class _ScoredToken {
  final int hash;
  final TokenCounts counts;
  final double salience;

  const _ScoredToken({
    required this.hash,
    required this.counts,
    required this.salience,
  });
}

/// Trains prior token distributions from clean public corpora (SpamAssassin, Enron).
class PriorTrainer {
  final Map<int, TokenCounts> _counts = {};
  int _totalSpam = 0;
  int _totalHam = 0;
  int _totalNewsletter = 0;
  int _totalInbox = 0;

  int get totalSpam => _totalSpam;
  int get totalHam => _totalHam;
  int get totalNewsletter => _totalNewsletter;
  int get totalInbox => _totalInbox;

  /// Ingests a message and updates token counts for the given label.
  void ingest(Message message, Label label) {
    switch (label) {
      case Label.spam:
        _totalSpam++;
        break;
      case Label.ham:
        _totalHam++;
        break;
      case Label.newsletter:
        _totalNewsletter++;
        break;
      case Label.inbox:
        _totalInbox++;
        break;
    }

    final normalized = Normalizer.normalize(message);
    final tokens = Tokenizer.tokens(normalized);
    final seen = <int>{};

    for (final token in tokens) {
      final hash = Tokenizer.hashToken(token);
      if (seen.add(hash)) {
        final current = _counts[hash] ?? const TokenCounts();
        TokenCounts updated;
        switch (label) {
          case Label.spam:
            updated = current.copyWith(spam: current.spam + 1);
            break;
          case Label.ham:
            updated = current.copyWith(ham: current.ham + 1);
            break;
          case Label.newsletter:
            updated = current.copyWith(newsletter: current.newsletter + 1);
            break;
          case Label.inbox:
            updated = current.copyWith(inbox: current.inbox + 1);
            break;
        }
        _counts[hash] = updated;
      }
    }
  }

  /// Calculates the salience score for a token:
  ///   count * |log((s + 1)/(h + 1) * totalH/totalS)|
  static double calculateSalience(
    TokenCounts counts, {
    required int totalSpam,
    required int totalHam,
  }) {
    final s = counts.spam;
    final h = counts.ham;
    final count = counts.spam + counts.ham + counts.newsletter + counts.inbox;
    final effTotalS = totalSpam > 0 ? totalSpam : 1;
    final effTotalH = totalHam > 0 ? totalHam : 1;
    final totalRatio = effTotalH / effTotalS;

    final odds = ((s + 1.0) / (h + 1.0)) * totalRatio;
    return count * (math.log(odds)).abs();
  }

  /// Exports trained model as JSON map.
  ///
  /// - [minCount]: Minimum total occurrences across all classes to consider a token.
  /// - [maxTokens]: Maximum number of most informative tokens to retain, ranked
  ///   by `count * |log((s+1)/(h+1) * totalH/totalS)|`. If <= 0, no pruning is applied.
  /// - [scaleTo]: Scales all counts and totals so each class equals at most N messages.
  ///   Tokens that become 0 across all classes after scaling are dropped. If <= 0,
  ///   no scaling is applied.
  Map<String, dynamic> exportModel({
    int minCount = 2,
    int maxTokens = 20000,
    int scaleTo = 200,
  }) {
    // 1. Filter tokens with total count >= minCount
    final candidates = <int, TokenCounts>{};
    for (final entry in _counts.entries) {
      final c = entry.value;
      final total = c.spam + c.ham + c.newsletter + c.inbox;
      if (total >= minCount) {
        candidates[entry.key] = c;
      }
    }

    // 2. Rank by salience if maxTokens is set and candidate pool is larger
    List<MapEntry<int, TokenCounts>> retainedTokens;
    if (maxTokens > 0 && candidates.length > maxTokens) {
      final scored = candidates.entries.map((e) {
        final salience = calculateSalience(
          e.value,
          totalSpam: _totalSpam,
          totalHam: _totalHam,
        );
        return _ScoredToken(hash: e.key, counts: e.value, salience: salience);
      }).toList();

      scored.sort((a, b) {
        final cmp = b.salience.compareTo(a.salience);
        if (cmp != 0) return cmp;
        return a.hash.compareTo(b.hash);
      });

      retainedTokens = scored
          .take(maxTokens)
          .map((s) => MapEntry(s.hash, s.counts))
          .toList();
    } else {
      retainedTokens = candidates.entries.toList();
    }

    // 3. Scale counts and totals so each class equals at most scaleTo messages
    final bool applyScale = scaleTo > 0;
    final double scaleSpam = (applyScale && _totalSpam > scaleTo) ? (scaleTo / _totalSpam) : 1.0;
    final double scaleHam = (applyScale && _totalHam > scaleTo) ? (scaleTo / _totalHam) : 1.0;
    final double scaleNews = (applyScale && _totalNewsletter > scaleTo) ? (scaleTo / _totalNewsletter) : 1.0;
    final double scaleInbox = (applyScale && _totalInbox > scaleTo) ? (scaleTo / _totalInbox) : 1.0;

    final int scaledTotalSpam = (applyScale && _totalSpam > scaleTo) ? scaleTo : _totalSpam;
    final int scaledTotalHam = (applyScale && _totalHam > scaleTo) ? scaleTo : _totalHam;
    final int scaledTotalNews = (applyScale && _totalNewsletter > scaleTo) ? scaleTo : _totalNewsletter;
    final int scaledTotalInbox = (applyScale && _totalInbox > scaleTo) ? scaleTo : _totalInbox;

    final filteredTokens = <String, Map<String, int>>{};

    for (final entry in retainedTokens) {
      final c = entry.value;
      final s = applyScale ? (c.spam * scaleSpam).round() : c.spam;
      final h = applyScale ? (c.ham * scaleHam).round() : c.ham;
      final news = applyScale ? (c.newsletter * scaleNews).round() : c.newsletter;
      final inbox = applyScale ? (c.inbox * scaleInbox).round() : c.inbox;

      // Drop tokens where all counts become 0
      if (s == 0 && h == 0 && news == 0 && inbox == 0) {
        continue;
      }

      filteredTokens[entry.key.toString()] = {
        'spam': s,
        'ham': h,
        'newsletter': news,
        'inbox': inbox,
      };
    }

    return {
      'version': 1,
      'corpora': 'SpamAssassin-public, Enron-Spam',
      'trained_at': DateTime.now().toUtc().toIso8601String(),
      'total_spam': scaledTotalSpam,
      'total_ham': scaledTotalHam,
      'totals': {
        'spam': scaledTotalSpam,
        'ham': scaledTotalHam,
        'newsletter': scaledTotalNews,
        'inbox': scaledTotalInbox,
      },
      'raw_totals': {
        'spam': _totalSpam,
        'ham': _totalHam,
        'newsletter': _totalNewsletter,
        'inbox': _totalInbox,
      },
      'token_count': filteredTokens.length,
      'tokens': filteredTokens,
    };
  }

  /// Saves model to file.
  void saveToFile(
    File file, {
    int minCount = 2,
    int maxTokens = 20000,
    int scaleTo = 200,
  }) {
    final data = exportModel(
      minCount: minCount,
      maxTokens: maxTokens,
      scaleTo: scaleTo,
    );
    file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(data));
  }

  /// Populates a default clean prior model if no local corpus directory is available.
  static Map<String, dynamic> createDefaultModel() {
    final trainer = PriorTrainer();

    // Seed exemplary spam indicators
    final spamSamples = [
      'Subject: Urgent inheritance payout claim\n\nDear friend, you have won \$1,000,000 lottery inheritance. Click link to verify crypto wallet payout immediately.',
      'Subject: Act now! Cheap pills and luxury replica watches\n\nBuy cheap discount meds online without prescription. Limited time bonus casino offer.',
      'Subject: Account suspended! Confirm credentials\n\nYour account has been temporarily restricted. Verify your password and billing info here to avoid termination.',
    ];
    for (final s in spamSamples) {
      trainer.ingest(Message(headers: {'subject': ['Urgent alert']}, textBody: s), Label.spam);
    }

    // Seed exemplary ham indicators
    final hamSamples = [
      'Subject: Project status sync notes\n\nHi team, attached are the meeting minutes and project timeline. Please review the pull request and deliver feedback.',
      'Subject: Lunch tomorrow?\n\nHey, let me know if you are free for lunch around noon. We can discuss the quarterly roadmap.',
      'Subject: Invoice #4512 details\n\nPlease find attached the verified invoice for software consulting services. Thanks for your business.',
    ];
    for (final h in hamSamples) {
      trainer.ingest(Message(headers: {'subject': ['Update']}, textBody: h), Label.ham);
      trainer.ingest(Message(headers: {'subject': ['Update']}, textBody: h), Label.inbox);
    }

    // Seed exemplary newsletter indicators
    final newsletterSamples = [
      'Subject: Weekly Tech Digest #42\nList-Unsubscribe: <https://news.example.com/unsub>\nList-Id: <tech.news.example.com>\nPrecedence: bulk\n\nHere is your weekly edition of engineering stories. View in browser. You received this because you subscribed.',
    ];
    for (final n in newsletterSamples) {
      trainer.ingest(Message(
        headers: {
          'subject': ['Weekly Tech Digest'],
          'list-unsubscribe': ['<https://news.example.com/unsub>'],
          'list-id': ['<tech.news.example.com>'],
          'precedence': ['bulk'],
        },
        textBody: n,
      ), Label.newsletter);
    }

    return trainer.exportModel(minCount: 1, maxTokens: 20000, scaleTo: 200);
  }
}
