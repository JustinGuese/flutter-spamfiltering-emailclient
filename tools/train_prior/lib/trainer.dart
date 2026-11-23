import 'dart:convert';
import 'dart:io';
import 'package:spam_core/spam_core.dart';

/// Trains prior token distributions from clean public corpora (SpamAssassin, Enron).
class PriorTrainer {
  final Map<int, TokenCounts> _counts = {};
  int _totalSpam = 0;
  int _totalHam = 0;
  int _totalNewsletter = 0;
  int _totalInbox = 0;

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

  /// Exports trained model as JSON map.
  Map<String, dynamic> exportModel({int minCount = 2}) {
    final filteredTokens = <String, Map<String, int>>{};

    for (final entry in _counts.entries) {
      final c = entry.value;
      final total = c.spam + c.ham + c.newsletter + c.inbox;
      if (total >= minCount) {
        filteredTokens[entry.key.toString()] = c.toMap();
      }
    }

    return {
      'version': 1,
      'corpora': 'SpamAssassin-public, Enron-Spam',
      'trained_at': DateTime.now().toUtc().toIso8601String(),
      'totals': {
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
  void saveToFile(File file, {int minCount = 2}) {
    final data = exportModel(minCount: minCount);
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

    return trainer.exportModel(minCount: 1);
  }
}
