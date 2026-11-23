# spam_core API Reference

`packages/spam_core` is a zero-dependency, pure Dart library providing on-device Robinson-Fisher Bayes classification, heuristic spam analysis, RFC 8601 authentication header parsing, and MinHash/LSH anonymous fingerprinting.

## Exports

All public APIs are exported from `package:spam_core/spam_core.dart`:

```dart
import 'package:spam_core/spam_core.dart';
```

### Core Contracts (`contracts.dart`)

| Type | Kind | Description |
|---|---|---|
| `Label` | `enum` | Classification categories: `spam`, `ham`, `newsletter`, `inbox`. |
| `Message` | `class` | Input email container: `headers`, `textBody`, optional `htmlBody`, `recipientAddrs`. Case-insensitive `getHeader(name)` and `firstHeader(name)`. |
| `Normalized` | `class` | Sanitized message view: `cleanedText`, `cleanedHtml`, `extractedUrls`, `senderDomain`, `isSenderFreemail`, `wordCount`. |
| `TokenCounts` | `class` | Occurrence counts across classes: `spam`, `ham`, `newsletter`, `inbox`. |
| `TokenStore` | `abstract class` | Asynchronous token count persistence interface: `counts(int hash)` and `apply(int hash, Label label, int delta)`. |
| `Evidence` | `class` | Explainable scoring component: `id` (e.g. `bayes`, `auth_dmarc_fail`), `weight`, `detail`. |
| `Verdict` | `class` | Final classification outcome: `label`, `spamScore` (0.0 to 1.0), and `List<Evidence>`. |
| `Fingerprints` | `class` | Cryptographic indicators: `bodyBands` (8x 64-bit MinHash LSH integers), `urlHashes`, optional `senderDomainHash`. |
| `Signals` | `class` | External hints: `advancedModelScore`, `communityBlocklistMatch`, `extra`. |

### Classification & Scoring (`combiner.dart`, `bayes.dart`)

- **`Classifier.score(Normalized normalized, TokenStore store, [Signals? signals, String? authservId]) -> Future<Verdict>`**:
  Runs Stage-A Robinson-Fisher Bayes scoring combined with authentication checks and heuristics. If `spamScore < 0.60`, evaluates Stage-B newsletter indicators.
  - Thresholds: `spamUnsureThreshold = 0.60`, `spamHighThreshold = 0.90`.
- **`Classifier.communityLogitBoost`** (`3.5`) and **`Classifier.scoreWithoutCommunity(double spamScore)`**:
  The logit the community blocklist signal adds, and the inverse: the score a message would have had without that signal. The app uses it to show what the blocklist added, from stored scores only.
- **`BayesClassifier.scoreTokens(List<int> tokenHashes, TokenStore store, ...) -> Future<BayesResult>`**:
  Evaluates token spam probabilities using Gary Robinson smoothed priors and combines them via Fisher's method with chi-squared upper tail survival analysis.
- **`BayesResult`**:
  Carries `score`, `hStat`, `sStat`, `hProbability`, `sProbability`, `tokenCount`, and `isUnsure`.

### Normalization & Tokenization (`normalizer.dart`, `tokenizer.dart`)

- **`Normalizer.normalize(Message message) -> Normalized`**:
  Strips recipient names/addresses and personal greetings, removes HTML tags, folds whitespace, extracts URLs, and parses sender domain.
- **`Tokenizer.tokens(Normalized normalized) -> List<String>`**:
  Extracts lowercase body words (length 2-30), OSB (Orthogonal Sparse Bigram) word pairs (window size 4), and prefixed header tokens (`subj:`, `from-dom:`, `url-dom:`, `ct:`, `x-mailer:`, `list-unsub:`, `list-id:`, `precedence:`).
- **`Tokenizer.hashToken(String token) -> int`**:
  Hashes a token string to a positive 63-bit integer using SHA-256 for cross-platform SQLite storage.

### Authentication & Heuristics (`auth_results.dart`, `heuristics.dart`)

- **`AuthResults.parse(Map<String, List<String>> headers, [String? targetAuthservId]) -> AuthResults`**:
  Parses RFC 8601 `Authentication-Results` headers for SPF, DKIM, and DMARC verdicts (`pass`, `fail`, `softfail`, `neutral`, `none`, etc.).
- **`Heuristics.evaluate(Normalized normalized) -> List<Evidence>`**:
  Inspects display-name email spoofing, brand impersonation, link text vs target URL mismatch, and disposable email domains.

### Fingerprinting (`fingerprint.dart`)

- **`Fingerprinter.fingerprints(Normalized normalized) -> Fingerprints`**:
  Produces anonymous cryptographic indicators:
  - `bodyBands`: 8 LSH bands computed from 32 MinHash permutations over word 3-shingles. Empty for bodies with fewer than 40 words.
  - `urlHashes`: 63-bit hashes of extracted URLs normalized to `eTLD+1` and `host + first path segment`.
  - `senderDomainHash`: Hash of sender domain (omitted for freemail domains).

### Utilities & Memory Store (`store_memory.dart`, `freemail_domains.dart`)

- **`MemoryTokenStore`**: In-memory `TokenStore` implementation for CLI tools, caching, and tests.
- **`isFreemailDomain(String? domain) -> bool`**: Returns true if the domain matches known freemail providers (e.g. Gmail, Yahoo, Proton, Outlook).

---

## Usage Example

The following snippet demonstrates initializing a token store, training tokens, normalizing an email, classifying it, and extracting fingerprints:

```dart
import 'package:spam_core/spam_core.dart';

Future<void> main() async {
  // 1. Initialize an in-memory token store (or `TokenStoreDrift` (SQLite) in production)
  final store = MemoryTokenStore();

  // 2. Pre-train a few known tokens
  final lotteryToken = Tokenizer.hashToken('lottery');
  final invoiceToken = Tokenizer.hashToken('invoice');
  await store.apply(lotteryToken, Label.spam, 50);
  await store.apply(invoiceToken, Label.ham, 50);

  // 3. Construct an incoming message
  final message = Message(
    headers: {
      'from': ['Lottery Notice <scam@spoofed-bank.com>'],
      'to': ['Target User <recipient@example.com>'],
      'subject': ['Claim your lottery winnings now'],
      'authentication-results': ['mx.example.com; dkim=fail; spf=fail; dmarc=fail'],
    },
    textBody: 'Congratulations! You won the international lottery reward! '
        'Claim your wire payout immediately at https://claim-prize.com/login. '
        'Failure to claim will forfeit all funds to the secondary winner.',
    recipientAddrs: ['recipient@example.com'],
  );

  // 4. Normalize the message (strips recipient details & greetings)
  final normalized = Normalizer.normalize(message);

  // 5. Classify the normalized message
  final verdict = await Classifier.score(normalized, store);

  print('Classification: ${verdict.label.name}'); // spam
  print('Spam Score: ${verdict.spamScore.toStringAsFixed(3)}');
  for (final ev in verdict.evidence) {
    print('  - [${ev.id}] weight: ${ev.weight.toStringAsFixed(2)}: ${ev.detail}');
  }

  // 6. Learn from user feedback
  final tokens = Tokenizer.tokens(normalized);
  for (final token in tokens) {
    final hash = Tokenizer.hashToken(token);
    await store.apply(hash, verdict.label, 1);
  }

  // 7. Extract privacy-preserving fingerprints for community telemetry
  final fp = Fingerprinter.fingerprints(normalized);
  print('Body LSH bands: ${fp.bodyBands.length}');
  print('URL hashes: ${fp.urlHashes.length}');
  print('Sender domain hash: ${fp.senderDomainHash}');
}
```

See also:
- [Spam Filter Architecture](../concepts/spam-filter.md)
- [Database Schema](database.md)
- [Backend Protocol](backend-protocol.md)
