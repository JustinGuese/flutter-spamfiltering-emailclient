import 'dart:async';

/// Classification labels supported by the engine.
enum Label { spam, ham, newsletter, inbox }

/// Represents an incoming or stored email message.
class Message {
  final Map<String, List<String>> headers;
  final String textBody;
  final String? htmlBody;
  final List<String> recipientAddrs;

  const Message({
    required this.headers,
    required this.textBody,
    this.htmlBody,
    this.recipientAddrs = const [],
  });

  /// Case-insensitive header retrieval.
  List<String> getHeader(String name) {
    final lower = name.toLowerCase();
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == lower) {
        return entry.value;
      }
    }
    return const [];
  }

  /// First value of a header or null.
  String? firstHeader(String name) {
    final values = getHeader(name);
    return values.isNotEmpty ? values.first : null;
  }
}

/// Normalized view of a message with personal details stripped.
class Normalized {
  final Message original;
  final String cleanedText;
  final String? cleanedHtml;
  final List<String> extractedUrls;
  final String? senderDomain;
  final bool isSenderFreemail;
  final int wordCount;

  const Normalized({
    required this.original,
    required this.cleanedText,
    this.cleanedHtml,
    this.extractedUrls = const [],
    this.senderDomain,
    this.isSenderFreemail = false,
    this.wordCount = 0,
  });
}

/// Counts of token occurrences across classes.
class TokenCounts {
  final int spam;
  final int ham;
  final int newsletter;
  final int inbox;

  const TokenCounts({
    this.spam = 0,
    this.ham = 0,
    this.newsletter = 0,
    this.inbox = 0,
  });

  TokenCounts copyWith({
    int? spam,
    int? ham,
    int? newsletter,
    int? inbox,
  }) {
    return TokenCounts(
      spam: spam ?? this.spam,
      ham: ham ?? this.ham,
      newsletter: newsletter ?? this.newsletter,
      inbox: inbox ?? this.inbox,
    );
  }

  Map<String, int> toMap() => {
    'spam': spam,
    'ham': ham,
    'newsletter': newsletter,
    'inbox': inbox,
  };
}

/// Abstract storage interface for token counts keyed by 64-bit hash.
abstract class TokenStore {
  FutureOr<TokenCounts> counts(int hash);
  FutureOr<void> apply(int hash, Label label, int delta);
}

/// Explanation for a single signal contributing to classification.
class Evidence {
  final String id;
  final double weight;
  final String detail;

  const Evidence({
    required this.id,
    required this.weight,
    required this.detail,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'weight': weight,
    'detail': detail,
  };
}

/// Classification outcome containing final label, spam probability, and evidence.
class Verdict {
  final Label label;
  final double spamScore;
  final List<Evidence> evidence;

  const Verdict({
    required this.label,
    required this.spamScore,
    this.evidence = const [],
  });
}

/// Anonymous fingerprints for community sharing and local matching.
class Fingerprints {
  final List<int> bodyBands; /* 8x u64 */
  final List<int> urlHashes;
  final int? senderDomainHash;

  const Fingerprints({
    required this.bodyBands,
    required this.urlHashes,
    this.senderDomainHash,
  });

  Map<String, dynamic> toJson() => {
    'body_bands': bodyBands,
    'url_hashes': urlHashes,
    'sender_domain_hash': senderDomainHash,
  };
}

/// Additional external signals passed into the classifier.
class Signals {
  final double? advancedModelScore;
  final bool? communityBlocklistMatch;
  final Map<String, dynamic>? extra;

  const Signals({
    this.advancedModelScore,
    this.communityBlocklistMatch,
    this.extra,
  });
}
