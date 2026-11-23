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
- **`classifier_test.dart`**: Tests end-to-end classification pipelines (including that `scoreWithoutCommunity` exactly undoes the blocklist's contribution), combining Bayesian probabilities with RFC 8601 `Authentication-Results` header parsing (SPF, DKIM, DMARC) and heuristic indicators.
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
  - Remote search: hits older than the synced mail and hits in unsynced folders (Archive) are imported; stored hits, hits newer than the synced UIDs, Junk and virtual folders are skipped; the import is capped per folder, newest first; queries only the device can answer (`is:spam`) never reach the server; an unreachable account is reported as failed.
- **`attachments_test.dart`**: Outgoing MIME (`multipart/alternative` without files, `multipart/mixed` with them, bytes and a non-ASCII file name surviving a render-and-parse round trip), which parts count as attachments (nested multiparts and their IMAP part numbers, named parts without a disposition, no text body or `Content-ID` logo, attached mails), `safeFileName` against hostile names (`../../.bashrc`, `C:\x\evil.exe`, `nul`, over-long), runnable file types, and the download cache.
- **`attachments_sync_test.dart`**: Attachments through the sync engine with a simulated server: files recorded on sync and row ids kept across re-syncs; one download, exact bytes, then served from the device; a message moved to Junk is found by `Message-ID` instead of its stale UID, and another message's bytes are never returned; a `Message-ID` that is not plain ASCII is never put into a search; mail stored before the table existed is filled in on first view; removing an account removes rows and cached files.
- **`attachment_ui_test.dart`**: The reader's attachment strip (names and sizes, tap downloads and opens, a failed open or download says so, a program shows a warning and `Cancel` downloads nothing) and the compose window (a forward opens with the original's files, each removable; sending with no recipient says so).
- **`reply_builder_test.dart`**: Reply, Reply All and Forward drafts: recipients (own address and duplicates removed, replies to your own mail go to its recipients), `Re:`/`Fwd:` subjects that never stack, quoting, and HTML-escaping of quoted text in the outgoing HTML part.
- **`protection_test.dart`**: The protection screen's numbers (spam split into filter-caught and community-only by re-scoring without the blocklist signal, your own verdicts counted as the filter's, newest-first capped list) and the screen itself: labelled sample data when nothing is caught yet, the four stages, the Pro upgrade card for free users only, and the Learned tab.
- **`search_view_test.dart`**: The Search tab: local hits appear at once, the server is asked only after typing pauses, the "searching" / "added N" / failed-with-retry status, and device-only queries are not sent to the server.
- **`search_test.dart`**: The query parser (prefix words, `"phrases"`, `from:` / `is:` / `has:` / `before:` / `after:`, the matching IMAP `SEARCH` criteria, junk input never errors) and the search itself against an in-memory database: matches in subject, sender, recipient and body, subject hits ranked above body hits, spam hidden unless asked for, the index following `INSERT OR REPLACE`, update and delete on `bodies`, and the backfill of mail stored before the index existed.
- **`verdict_controller_test.dart`**: A user verdict (and its undo, with the community report client stubbed so tests never reach the live backend) is written in a single SQLite transaction rather than one disk sync per token, and notifies the UI so lists and the reader rebuild.
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
