# Testing & Verification

DataFortress Mail includes automated test suites across the core Bayesian engine and the Flutter client, as well as offline tools for training and evaluating prior models.

---

## 1. Spam Core Tests (`packages/spam_core`)

The `spam_core` package is pure Dart and runs directly on the standalone Dart VM without Flutter dependencies.

### Running the Suite

Navigate to the `packages/spam_core` directory and run:

```bash
cd packages/spam_core
dart test
```

### Test Scope
The suite in `packages/spam_core/test/` covers:

- **`bayes_test.dart`**: Validates the Robinson-Fisher chi-squared combination algorithm against hand-computed reference values (`chi2UpperTail`), probability clamping, and multi-token combination stability.
- **`classifier_test.dart`**: Tests end-to-end classification pipelines, combining Bayesian probabilities with RFC 8601 `Authentication-Results` header parsing (SPF, DKIM, DMARC) and heuristic indicators.
- **`fingerprint_test.dart`**: Tests MinHash locality-sensitive hashing (LSH) over 32 permutations, verifying identical body bands across varying recipient names, URL normalization (stripping tracking queries and fragments), sender domain hashing, and freemail guard rules.
- **`normalizer_test.dart`**: Tests text extraction, HTML stripping, greeting and recipient address removal, orthogonal sparse bigram (OSB) generation, and `MemoryTokenStore` updates.

---

## 2. Flutter Application Tests (`app`)

The application test suite exercises UI components, state management, and the mail synchronization engine.

### Running the Suite

Navigate to the `app` directory and run:

```bash
cd app
flutter test
```

### Test Scope
The suite in `app/test/` covers:

- **`html_to_text_test.dart`**: Verifies that HTML bodies are accurately sanitized and stripped to plaintext, preserving paragraph boundaries and decoding HTML entities while ignoring markup artifacts.
- **`launch_gate_test.dart`**: Validates onboarding launch gating (`AppLaunchGate`), confirming that selecting "Maybe later" on the paywall directs first-time users to "Add Account" when no mail accounts exist, or directly to the mailbox when an account is configured.
- **`sync_engine_test.dart`**: Tests the IMAP synchronization engine against simulated mailboxes:
  - Initial sync stores inbox messages by real IMAP UID and ignores `Noselect` or virtual folders.
  - Subsequent syncs request only UIDs greater than the highest stored UID.
  - Legacy sequence-number cache rows are properly evicted.
  - Account deletion purges associated folders and cached messages while preserving other accounts.
  - Concurrent sync calls for the same account coalesce into a single connection.
  - Unresponsive IMAP servers time out instead of hanging indefinitely.
  - The Sent folder is listed and synced without classification; virtual folders are not listed.
  - `Cc` addresses are stored, and an existing `messages` table without `cc_addrs` is migrated.
- **`reply_builder_test.dart`**: Reply, Reply All and Forward drafts: recipients (own address and duplicates removed, replies to your own mail go to its recipients), `Re:`/`Fwd:` subjects that never stack, quoting, and HTML-escaping of quoted text in the outgoing HTML part.
- **`verdict_bar_test.dart`**: Validates the three-way `VerdictBar` UI widget (Inbox, Newsletter, Spam), checking tactile state changes and accessibility semantics labels.

---

## 3. Prior Model CLI Tool (`tools/train_prior`)

The `tools/train_prior` package is a standalone Dart command-line utility used to generate default prior models or ingest external EML message corpora to train and evaluate Bayesian priors.

### CLI Commands

Navigate to the tool directory:

```bash
cd tools/train_prior
```

#### Generate Default Seed Prior
Emits the clean baseline prior model containing foundational token frequencies:

```bash
dart run bin/train_prior.dart generate-default -o prior_model.json
```

#### Train From Corpora
Ingests directories of raw EML files sorted by label and exports a combined JSON prior:

```bash
dart run bin/train_prior.dart train \
  --spam-dir path/to/spam/eml \
  --ham-dir path/to/ham/eml \
  --news-dir path/to/newsletters/eml \
  --min-count 2 \
  -o prior_model.json
```

- `--min-count`: Minimum number of times a token must appear across messages to be retained in the model (filters noise).

#### Evaluate Model Accuracy
Evaluates a trained model against an independent validation corpus:

```bash
dart run bin/train_prior.dart eval \
  --model prior_model.json \
  --spam-dir path/to/test-spam \
  --ham-dir path/to/test-ham
```

Outputs confusion matrix statistics: True Positives (Spam), False Positives (Ham classified as Spam), and False Negatives.

!!! warning "Corpus Licensing"
    When assembling email corpora for model training, ensure that dataset licenses permit redistribution of derived token n-grams. Never use corpora with restrictive non-commercial terms (such as TREC) for models intended for public distribution. For details, see [Train Prior Reference](../reference/train-prior.md).
