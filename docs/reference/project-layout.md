# Project Layout Reference

This document provides an annotated map of the repository generated from `git ls-files`.

The codebase is structured as a monorepo containing the Flutter cross-platform desktop/mobile client, pure Dart spam filter package, and offline prior training tooling.

---

## Monorepo Directory Structure

```
├── .vscode/               # Editor workspace settings
├── PLAN-docs.md           # Documentation overhaul specification
├── PLAN.md                # Project roadmap and milestone tracker
├── README.md              # Repository overview and quickstart
├── docs/                  # MkDocs documentation source
├── app/                   # Flutter application client
├── packages/
│   └── spam_core/         # Pure Dart spam classification library
└── tools/
    └── train_prior/       # CLI utility for training prior models
```

---

## 1. Flutter Application (`app/`)

The client email application built with Flutter and Riverpod.

### `app/lib/` Architecture

| Directory / File | Description |
|---|---|
| `lib/api/api_client.dart` | Authenticated Dio HTTP provider injecting Firebase ID tokens for hosted services. |
| `lib/app/` | Application root lifecycle: `app.dart`, `bootstrap.dart`, `router.dart`, `log.dart`, plus the user-facing string tables `strings.dart` and `ui_strings.dart`. |
| `lib/community/` | Anonymous community reporting: `report_client.dart`, `blocklist_sync.dart`, `pow.dart` (proof of work), `app_check.dart`. |
| `lib/db/` | On-device SQLite persistence: `database.dart` (opens the file and creates the schema with plain SQL). `tables.dart` is an unused Drift-style declaration of the same schema. |
| `lib/filter/` | Bridge between app and `spam_core`: `filter_service.dart` (classify and persist verdicts), `verdict_controller.dart` (user verdicts and training), `token_store_drift.dart` (SQLite-backed token counts), `protection_stats.dart` (replays stored classifications for the protection screen), `cold_start.dart`, `imap_flags.dart`. |
| `lib/funnel/` | Launch funnel: `funnel_config.dart` (onboarding, then a skippable paywall) and `launch_gate.dart` (the onboarding screen is the shared `df_onboarding` carousel configured here). |
| `lib/mail/` | IMAP and SMTP protocol engine: `sync_engine.dart` (account sync and `searchRemote`, the server-side search), `imap_service.dart` (includes `searchUids` / `fetchByUids`), `smtp_service.dart` (includes `buildOutgoingMessage`), `attachments.dart` (attachment extraction, safe file names, the download cache, the outgoing-file model), `reply_builder.dart` (Reply / Reply All / Forward drafts), `account_repository.dart` (credentials, OAuth token refresh), `autodiscover.dart`, `mail_auth.dart`, `html_sanitizer.dart`, `html_to_text.dart`, and `oauth/` (`oauth_config.dart`, `oauth_flow.dart`, `oauth_flow_native.dart`, `oauth_flow_loopback.dart`, `oauth_service.dart`, `oauth_types.dart`: Google and Microsoft sign-in on top of the shared `df_oauth`). |
| `lib/notifications/` | New-mail notifications: `notify_types.dart` (`NotifyMode`, `NewMail`), `notify_prefs.dart` (settings-backed providers), `new_mail_notifier.dart` (batching per mode), `mail_notification_service.dart` (adapter over the shared `df_notifications`). |
| `lib/platform/` | Native platform abstraction: `platform_services.dart` (the contract plus shared UI-state providers), `native_services.dart` (iOS, Android, macOS), `desktop_services.dart` (Windows, Linux). |
| `lib/premium/` | Pro features: `filter_sync.dart` (E2EE CRDT PN-counters), `crdt_counters.dart`, `sync_key.dart`, `onnx_scorer.dart`, `model_downloader.dart`. |
| `lib/search/` | Search tab logic: `search_query.dart` (parses the search box into an FTS5 `MATCH` expression, SQL filters and IMAP `SEARCH` criteria) and `search_service.dart` (runs it against the `search_index` table and ranks with BM25). |
| `lib/theme/` | Ledger Desk design system: `app_theme.dart`, `app_brand.dart`, `app_type.dart`. |
| `lib/ui/` | Flutter widget views and components: |
| ├── `account_setup/` | IMAP/SMTP account connection wizard. |
| ├── `common/` | Reusable UI widgets: `formats.dart`, `mail_queries.dart`, `app_parts.dart`. |
| ├── `compose/` | Email composer (`compose_view.dart`), optionally prefilled from a reply or forward draft; attaches files and sends them. |
| ├── `filter/` | Spam inspection: `evidence_sheet.dart`, `verdict_bar.dart`, `ledger_card.dart`, `stamp.dart`, `sharing_notice.dart`. |
| ├── `mailbox/` | Mailbox folder view and message list: `mailbox_view.dart`, `message_row.dart`. |
| ├── `protection/` | "Your protection" full-screen view opened from the sidebar filter card: `protection_view.dart` (tabs, caught list, learned), `protection_story.dart` (the four-stage replay), `pro_panel.dart` (Pro stage and upgrade card). |
| ├── `search/` | The Search tab: `search_view.dart` (search box, results list, server-search status, reader pane). |
| ├── `premium/` | Pro upgrade, device pairing, and subscription UI (`premium_gate.dart`, `sync_tile.dart`). |
| ├── `reader/` | Message reading pane (Reply / Reply All / Forward buttons, full-screen view) with remote image blocker: `reader_view.dart`, `attachment_strip.dart` (the received files: open, save), `image_block_banner.dart`. |
| ├── `settings/` | User preferences: `settings_view.dart`, `accounts_tile.dart`, `appearance_tile.dart`, `sharing_tile.dart`, `notifications_tile.dart`. |
| └── `shell/` | Responsive window layouts: `three_pane_layout.dart`, `folders_sidebar.dart`, `nav_shell.dart`. |

### Platform Runner Projects

- `app/android/`: Android build configuration, manifests, and splash assets.
- `app/ios/`: iOS Xcode workspace, project files, and application delegates.
- `app/linux/`: CMake build files, GTK shell runner (`main.cc`, `my_application.cc`).
- `app/macos/`: macOS Xcode workspace, entitlements for keychain and network access, `MainFlutterWindow.swift`.
- `app/windows/`: CMake configuration and Win32 window host runner (`main.cpp`, `win32_window.cpp`).

### App Assets (`app/assets/`)

- `fonts/`: Bundled SIL OFL typography (`Fraunces.ttf`, `JetBrainsMono.ttf`, `PublicSans.ttf`).
- `icon/`: Application icons (`icon_adaptive.png`, `icon_rounded.png`, `icon_square.png`).
- `prior_model.json`: Bundled initial hand-curated seed Bayesian model.

---

## 2. Spam Core Package (`packages/spam_core/`)

A zero-dependency, pure Dart package designed for standalone use and client integration.

| File | Purpose |
|---|---|
| `lib/spam_core.dart` | Library entry point and public export manifest. |
| `lib/src/contracts.dart` | Data structures: `Label`, `Message`, `Normalized`, `Verdict`, `Evidence`, `TokenStore`, `Fingerprints`. |
| `lib/src/normalizer.dart` | Text normalization, recipient token stripping, and URL extraction. |
| `lib/src/tokenizer.dart` | Tokenizer generating unigrams, OSB bigrams, and prefixed header tokens. |
| `lib/src/bayes.dart` | Robinson-Fisher chi-squared naive Bayes classifier. |
| `lib/src/combiner.dart` | Multi-stage pipeline combining Bayes, authentication headers, heuristics, and newsletter detection. |
| `lib/src/auth_results.dart` | RFC 8601 `Authentication-Results` header parser (SPF, DKIM, DMARC). |
| `lib/src/heuristics.dart` | Deterministic heuristics (link mismatch, display-name spoofing, disposable domains). |
| `lib/src/fingerprint.dart` | MinHash 32 / LSH 8x4 body bands and URL hashing. |
| `lib/src/freemail_domains.dart` | Fast lookup set of common freemail provider domains. |
| `lib/src/store_memory.dart` | In-memory token store for testing and CLI usage. |
| `test/` | Unit test suite: `bayes_test.dart`, `classifier_test.dart`, `fingerprint_test.dart`, `normalizer_test.dart`. |

---

## 3. Prior Training Tool (`tools/train_prior/`)

Command-line tool used to train, evaluate, and generate prior JSON models from email corpora.

| File | Purpose |
|---|---|
| `bin/train_prior.dart` | CLI entry point implementing `train`, `eval`, and `generate-default` subcommands. |
| `lib/corpus_reader.dart` | RFC 822 / EML directory parser. |
| `lib/trainer.dart` | Prior token count accumulator and JSON serializer. |
| `lib/evaluator.dart` | Accuracy and false-positive evaluation against labeled test sets. |

---

## 4. Documentation Site (`docs/`)

Material for MkDocs source files:
- `index.md`: Documentation homepage.
- `getting-started/`: Installation prerequisites, configuration flags, and testing instructions.
- `concepts/`: Deep-dive architectural concepts, privacy model, spam filter internals, community network, and Pro features.
- `reference/`: Public APIs, HTTP protocol contracts, database tables, and tool CLI flags.
- `contributing/`: Contribution guidelines, design system rules, and platform-specific compilation notes.
- `open-source.md`: Open-core model explanation and third-party license notices.

See also:
- [Spam Core API](spam-core-api.md)
- [Database Schema](database.md)
- [Backend Protocol](backend-protocol.md)
- [Train Prior Tool](train-prior.md)
