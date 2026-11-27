# Train Prior Tool Reference

The `tools/train_prior` package is a Dart command-line tool used to train, evaluate, and generate prior Bayesian models from RFC 822 / EML email datasets.

Trained models are output as JSON files consumed by `packages/spam_core` and bundled into `app/assets/prior_model.json`.

---

## Usage & Commands

The tool is invoked via `dart run`:

```bash
cd tools/train_prior
dart run bin/train_prior.dart <command> [options]
```

Or view global and command-specific help:

```bash
dart run bin/train_prior.dart --help
dart run bin/train_prior.dart train --help
```

---

### 1. `train`

Trains token frequency distributions across spam, ham, and newsletter corpora, selects the most informative features using log-odds salience ranking, scales class totals to prevent cold-start ossification, and discards low-frequency noise.

```bash
dart run bin/train_prior.dart train \
  --spam-dir=/path/to/spam \
  --ham-dir=/path/to/ham \
  --news-dir=/path/to/newsletters \
  --output=prior_model.json \
  --min-count=2 \
  --max-tokens=20000 \
  --scale-to=200
```

#### Options:
- `--spam-dir` (string): Directory containing spam `.eml` or RFC 822 files.
- `--ham-dir` (string): Directory containing legitimate ham `.eml` files.
- `--news-dir` (string, optional): Directory containing newsletter `.eml` files.
- `-o`, `--output` (string): Output JSON model path (defaults to `prior_model.json`).
- `--min-count` (int): Minimum total occurrences required across classes for a token to be considered (defaults to `2`). Discards single-occurrence ephemeral tokens.
- `--max-tokens` (int): Maximum number of top informative tokens to retain (defaults to `20000`). Tokens are ranked by information salience:
  $$\text{salience} = \text{count} \times \left| \log\left( \frac{s + 1}{h + 1} \times \frac{\text{totalH}}{\text{totalS}} \right) \right|$$
  where $s$ and $h$ are token spam and ham counts, and $\text{totalS}$ and $\text{totalH}$ are the total spam and ham messages ingested. Set to `0` for unlimited.
- `--scale-to` (int): Scale all token counts and message totals so that each class equals at most $N$ messages (defaults to `200`). Any token whose counts round down to `0` across all classes is dropped. Set to `0` to disable scaling.
- `--corpora` (string): Corpus names recorded in the model file's `corpora` field (defaults to `unspecified`).

#### Why `--scale-to` Matters
A real training corpus often contains 10,000 to 50,000+ messages. If unscaled totals and counts were imported directly into the user's database:
- The classifier would require thousands of explicit user verdicts before the user's personal corrections could meaningfully shift token probabilities.
- Scaling each class to at most $N = 200$ preserves the relative conditional likelihoods and discriminative power of the prior model while allowing on-device learning: a user's 5–10 corrections on recurring emails quickly outweigh the prior.

---

### 2. `eval`

Evaluates classification metrics (precision, recall, false positive rate) of a trained model against a test dataset.

```bash
dart run bin/train_prior.dart eval \
  --model=prior_model.json \
  --spam-dir=/path/to/test_spam \
  --ham-dir=/path/to/test_ham
```

#### Options:
- `-m`, `--model` (string): Path to the trained model JSON file (defaults to `prior_model.json`).
- `--spam-dir` (string): Test directory containing spam messages.
- `--ham-dir` (string): Test directory containing ham messages.

The evaluator outputs accuracy, spam precision, spam recall, and logs false positives where legitimate ham was incorrectly flagged.

---

### 3. `generate-default`

Generates a minimal, clean default prior model without ingesting external email files:

```bash
dart run bin/train_prior.dart generate-default --output=prior_model.json
```

#### Options:
- `-o`, `--output` (string): Output file path (defaults to `prior_model.json`).

---

## Recommended Workflow: Training from Real Corpora

Follow this step-by-step workflow when updating the bundled prior model with clean, public corpora:

### Step 1: Download License-Clean Corpora
Ensure datasets allow redistribution of statistical n-gram derivatives (see [Corpora Licensing](#corpora-licensing--privacy-caveats) below):
- **Apache SpamAssassin Public Corpus**:
  Download `easy_ham` and `spam_2` archives from [SpamAssassin Public Corpus](https://spamassassin.apache.org/old/publiccorpus/):
  ```bash
  mkdir -p /tmp/corpus/raw && cd /tmp/corpus/raw
  curl -O https://spamassassin.apache.org/old/publiccorpus/20030228_easy_ham.tar.bz2
  curl -O https://spamassassin.apache.org/old/publiccorpus/20050311_spam_2.tar.bz2
  ```
- **Enron-Spam Dataset**:
  Download pre-cleaned Enron ham and spam splits from [AUEB Enron-Spam](http://nlp.cs.aueb.gr/software_and_datasets/Enron-Spam/index.html).

### Step 2: Unpack and Organize Train/Test Splits
Extract the files into dedicated training and evaluation directories:
```bash
mkdir -p /tmp/corpus/train/ham /tmp/corpus/train/spam
mkdir -p /tmp/corpus/test/ham /tmp/corpus/test/spam

tar -xjf 20030228_easy_ham.tar.bz2 -C /tmp/corpus/raw/
tar -xjf 20050311_spam_2.tar.bz2 -C /tmp/corpus/raw/

# Reserve an 80/20 train/test split
```

### Step 3: Run Training
Execute `train_prior train` with `--max-tokens=20000` and `--scale-to=200`:
```bash
cd tools/train_prior
dart run bin/train_prior.dart train \
  --spam-dir=/tmp/corpus/train/spam \
  --ham-dir=/tmp/corpus/train/ham \
  --max-tokens=20000 \
  --scale-to=200 \
  --output=/tmp/prior_model.json
```

### Step 4: Evaluate Model Performance
Validate against the held-out test split:
```bash
dart run bin/train_prior.dart eval \
  --model=/tmp/prior_model.json \
  --spam-dir=/tmp/corpus/test/spam \
  --ham-dir=/tmp/corpus/test/ham
```
Verify that:
- Spam recall (score ≥ 0.60) is at least 95 %.
- Ordinary ham moved to Junk (score ≥ 0.90) stays around 1 % or lower; read deliberately spam-like newsletters ("hard ham") separately.
- Then run the app's prior gate (`app/test/prior_gate_test.dart`) with the candidate bundled: a corpus hold-out alone does not show whether modern mail is safe.

### Step 5: Bundle Verified Model into App
Once verified by the reviewer:
```bash
cp /tmp/prior_model.json app/assets/prior_model.json
```
Run `flutter test` in `app/` (including `test/prior_gate_test.dart`) to ensure the prior gate, cold-start and sync tests pass with the updated model.

---

## Model JSON File Format

The output JSON file contains top-level message totals, category totals, and token hashes mapped to their respective category counts:

```json
{
  "version": 1,
  "corpora": "SpamAssassin public corpus (20030228 + 20050311)",
  "trained_at": "2026-11-27T17:00:00.000Z",
  "total_spam": 200,
  "total_ham": 200,
  "totals": {
    "spam": 200,
    "ham": 200,
    "newsletter": 0,
    "inbox": 0
  },
  "raw_totals": {
    "spam": 14200,
    "ham": 28400,
    "newsletter": 0,
    "inbox": 0
  },
  "token_count": 18450,
  "tokens": {
    "5829103948102938": {
      "spam": 142,
      "ham": 3,
      "newsletter": 0,
      "inbox": 0
    },
    "2910481029384719": {
      "spam": 1,
      "ham": 89,
      "newsletter": 4,
      "inbox": 85
    }
  }
}
```

When loaded by `CorpusEvaluator.loadModel(file)` or `TokenStoreDrift.seedPriorModelIfEmpty()`, keys are resolved (supporting both 64-bit integer hashes and legacy string tokens) and seeded into the token database alongside `total_spam` and `total_ham`.

---

## Corpora Licensing & Privacy Caveats

When training prior models intended for distribution or bundling into open-source software, datasets must be scrutinized for legal, copyright, and privacy restrictions:

### 1. TREC Corpora: NEVER Distribute Models
> [!CAUTION]
> **Do NOT train distributed models on TREC email corpora** (such as TREC 2005, 2006, or 2007 Spam Track datasets).
>
> TREC data distribution agreements contain strict academic-use-only and non-commercial clauses. Bundling derivative token models trained on TREC data violates the license agreement and prevents commercial or open-source distribution.

### 2. SpamAssassin Public Corpus
- The SpamAssassin project offers the public corpus to spam-filter developers. Copyright in the message text stays with the original senders, so only derived statistics are distributed: the bundled prior holds hashed token counts, never text.
- Never send corpus mail into a live mail system (the corpus readme asks for this explicitly).

### 3. Enron Email Dataset
- The Enron dataset is in the public domain following the Federal Energy Regulatory Commission (FERC) investigation.
- Use only cleaned, sanitized distributions. Be mindful that real personal emails and employee correspondence are contained within; ensure tokenization does not leak individual email addresses into distributed priors.

### 4. Bundled Prior
`app/assets/prior_model.json` is still the **hand-curated seed** (no message totals). A prior trained on the SpamAssassin public corpus scored well on that corpus's own hold-out (97.4 % recall, 1.0 % of ordinary ham moved to Junk) but moved 10 of the 30 modern synthetic ham fixtures to Junk: 2002 mailing-list ham has no order, billing or appointment mail, so that language looked like spam. Before replacing the seed, run `flutter test test/prior_gate_test.dart` in `app/` with the candidate in place; it must pass. A corpus with modern transactional ham is needed for a trained prior to pass.

`CorpusReader` MIME-decodes every message with `enough_mail` (the parser the app's sync uses), so a prior is trained on the same decoded text the app classifies. Non-UTF-8 files are read with malformed bytes replaced instead of being skipped. Record the corpus with `--corpora`.

See also:
- [Spam Core API](spam-core-api.md)
- [Spam Filter Concepts](../concepts/spam-filter.md)
- [Project Layout](project-layout.md)
