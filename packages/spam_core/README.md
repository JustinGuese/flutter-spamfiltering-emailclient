# spam_core

Pure Dart spam filtering and anonymous fingerprinting engine.

`spam_core` provides Robinson-Fisher Bayesian text classification, email message normalization, SPF/DKIM/DMARC authentication parsing, link and heuristic analysis, and privacy-preserving MinHash LSH fingerprinting for email messages. It has zero Flutter or platform dependencies and runs anywhere Dart runs.

## Features

- **Robinson-Fisher Bayes Classifier**: Combines token probabilities with chi-square statistics for robust confidence scoring across multiple labels (`spam`, `ham`, `newsletter`, `inbox`).
- **Email Normalization & Tokenization**: Strips personal identifiers, recipient addresses, greeting boilerplate, and extracts sanitized words, domains, and URLs.
- **Header Authentication Parser**: Parses RFC 8601 `Authentication-Results` headers (SPF, DKIM, DMARC verdicts).
- **Privacy-Preserving Fingerprinting**: Generates MinHash Locality-Sensitive Hashing (LSH) band hashes from message bodies and URLs, suitable for zero-knowledge spam reporting without disclosing message contents.
- **Heuristic Scorer**: Evaluates freemail usage, reply-to mismatches, link counts, and suspicious TLDs.

## Installation

Add `spam_core` to your `pubspec.yaml`:

```yaml
dependencies:
  spam_core:
    path: ../packages/spam_core
```

Or when consuming via Git:

```yaml
dependencies:
  spam_core:
    git:
      url: https://github.com/JustinGuese/datafortress.git
      path: packages/spam_core
```

## Quick Start

```dart
import 'package:spam_core/spam_core.dart';

void main() async {
  // 1. Initialize a token store (in-memory or persistent)
  final store = MemoryTokenStore();

  // 2. Create the classifier
  final classifier = BayesClassifier(store);

  // 3. Train on a message
  final sampleSpam = Message(
    headers: {'from': ['lottery@promo-winner.xyz']},
    textBody: 'Congratulations! You have won ten thousand dollars wire transfer.',
  );
  await classifier.train(sampleSpam, Label.spam);

  // 4. Classify an incoming message
  final incoming = Message(
    headers: {'from': ['claims@promo-winner.xyz']},
    textBody: 'Claim your lottery funds today!',
  );
  final score = await classifier.score(incoming);
  print('Spam score: ${score.robinsonScore}');

  // 5. Compute privacy-preserving fingerprints
  final fingerprints = Fingerprinter.fingerprint(incoming);
  print('Body band hashes: ${fingerprints.bodyBandHashes}');
}
```

## Running Tests

Run the pure Dart test suite:

```bash
dart test
```

## License

Licensed under the [Apache License, Version 2.0](LICENSE).
