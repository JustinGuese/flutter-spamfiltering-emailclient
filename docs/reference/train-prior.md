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

### 1. `train`

Trains token frequency distributions across spam, ham, and newsletter corpora, filtering out low-frequency noise.

```bash
dart run bin/train_prior.dart train \
  --spam-dir=/path/to/spam \
  --ham-dir=/path/to/ham \
  --news-dir=/path/to/newsletters \
  --output=prior_model.json \
  --min-count=2
```

#### Options:
- `--spam-dir` (string): Directory containing spam `.eml` or RFC 822 files.
- `--ham-dir` (string): Directory containing legitimate ham `.eml` files.
- `--news-dir` (string, optional): Directory containing newsletter `.eml` files.
- `-o`, `--output` (string): Output JSON model path (defaults to `prior_model.json`).
- `--min-count` (int): Minimum total occurrences required across classes for a token to be retained (defaults to `2`). Discards single-occurrence ephemeral tokens.

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

## Model JSON File Format

The output JSON file maps 63-bit integer token hashes (serialized as decimal strings) to their respective category counts:

```json
{
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
```

When loaded by `CorpusEvaluator.loadModel(file)` or `TokenStoreDrift.loadPrior(json)`, keys are parsed into 64-bit integer hashes and populated into the token store.

---

## Corpora Licensing & Privacy Caveats

When training prior models intended for distribution or bundling into open-source software, datasets must be scrutinized for legal, copyright, and privacy restrictions:

### 1. TREC Corpora: NEVER Distribute Models
> [!CAUTION]
> **Do NOT train distributed models on TREC email corpora** (such as TREC 2005, 2006, or 2007 Spam Track datasets).
>
> TREC data distribution agreements contain strict academic-use-only and non-commercial clauses. Bundling derivative token models trained on TREC data violates the license agreement and prevents commercial or open-source distribution.

### 2. SpamAssassin Public Corpus
- The Apache SpamAssassin public corpus is broadly used for anti-spam research.
- Verify terms and remove personal identifiable information (PII) before publishing derivative statistics.

### 3. Enron Email Dataset
- The Enron dataset is in the public domain following the Federal Energy Regulatory Commission (FERC) investigation.
- Use only cleaned, sanitized distributions. Be mindful that real personal emails and employee correspondence are contained within; ensure tokenization does not leak individual email addresses into distributed priors.

### 4. Seed Prior Notice
The bundled file `app/assets/prior_model.json` included in this repository is a **minimal, hand-curated seed model** containing baseline structural tokens, not a large corpus-trained model. Production deployments should either train against licensed internal corpora or allow the client to learn from the user's personal mailbox and community blocklists.

See also:
- [Spam Core API](spam-core-api.md)
- [Spam Filter Concepts](../concepts/spam-filter.md)
- [Project Layout](project-layout.md)
