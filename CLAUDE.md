# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

The open-source client of an open-core product: a Flutter IMAP/SMTP email client with an on-device spam filter. Three Dart projects, no workspace file, each with its own `pubspec.yaml`:

- `app/` — the Flutter app (package `spamfiltering_emailclient`; iOS, Android, macOS, Windows, Linux).
- `packages/spam_core/` — pure Dart (no Flutter): normalizer, tokenizer, Robinson-Fisher Bayes, auth-header and heuristic signals, MinHash fingerprints. Must stay free of Flutter imports.
- `tools/train_prior/` — Dart CLI that trains/evaluates `app/assets/prior_model.json` (`train`, `eval`, `generate-default`).

The hosted backend (community blocklist, filter sync, entitlements) is **proprietary and lives in a separate private repo**. Never add backend code, infra, env files or secrets here. This repo only holds the client side of the protocol, documented in `docs/reference/backend-protocol.md`. Git history before the split still contains the old `backend/` folder.

## Commands

```bash
# App (run from app/)
flutter pub get
GDK_BACKEND=x11 flutter run -d linux --debug     # GDK_BACKEND needed under WSL; Linux also needs gnome-keyring/libsecret
flutter analyze                                    # platform dirs (android/ios/macos/linux/windows) are excluded
flutter test
flutter test test/sync_engine_test.dart            # single file
flutter test --plain-name "Maybe later"            # single test by name
PREVIEW_OUT=/tmp/preview flutter test tool/preview/preview_test.dart   # renders screens to PNGs; not part of the suite

# spam_core (from packages/spam_core/)
dart test
dart test test/bayes_test.dart

# Docs (from repo root)
pip install -r requirements-docs.txt
mkdocs serve
mkdocs build --strict        # what CI runs; broken nav/links fail the build

# Regenerate generated assets (from app/)
dart run flutter_launcher_icons
dart run flutter_native_splash:create
```

Backend URL is a compile-time define: `--dart-define=BACKEND_URL=...` (default: the hosted backend, `https://emailprogram-spamfilter-backend-api.datafortress.cloud`; defined once in `app/lib/api/backend_config.dart`); native builds also read `REVENUECAT_API_KEY`. Without a backend the mail client and local filter still work; community sync and Pro do not.

OAuth sign-in client IDs are compile-time defines too (`GOOGLE_OAUTH_CLIENT_ID_IOS` (also macOS) / `_ANDROID` / `_DESKTOP`, `GOOGLE_OAUTH_CLIENT_SECRET_DESKTOP`, `MS_OAUTH_CLIENT_ID`; read in `app/lib/mail/oauth/oauth_config.dart`). Without them the sign-in buttons show "not configured in this build" and password accounts work as before.

## Local setup gotchas

- `app/pubspec.yaml` depends on `df_flutter_shared` by **git** (`ref: main`, no tags). For local work, `app/pubspec_overrides.yaml` (gitignored, never commit) points those packages at a sibling checkout. Its relative paths depend on where the repo sits; if `pub get` says a `df_*` path doesn't exist, the folder layout changed — fix the `../` depth.
- After moving the repo, delete `app/build/linux` — the CMake cache bakes in absolute paths.
- Icon/splash sources in `app/assets/icon/` are derived from `logo.png` (square crop for iOS, transparent rounded for desktop, padded for Android adaptive). The derivation script is not in the repo; changing the logo means regenerating those three files, then running the two generators above.

## Architecture (the parts that span files)

**Data flow of a mail.** `AppBootstrap` (`app/lib/app/bootstrap.dart`) starts a 6-hour blocklist sync and a 5-minute account sync, and syncs on app resume. `SyncEngine` pulls IMAP mail into SQLite, sanitizes HTML, and calls `FilterService.classifyMessage` → `spam_core` (`Normalizer` → `Fingerprinter` → `Classifier.score`) plus a `CommunityMatcher` check against the local blocklist. The verdict and evidence are written back to the `messages`/`classifications` tables. User verdicts go through `VerdictController`, which retrains the token counts (decrement old label, increment new), moves the message on the server, and triggers the debounced Pro filter upload.

**No reactive DB layer.** Storage is plain `sqlite3` with hand-written SQL run on `db.db.select/execute` from services and widgets alike. There is no change stream: anything that writes mail must bump `mailRevisionProvider`, and list widgets `ref.watch` it to rebuild. If a screen doesn't update after a write, this is why.

**Batch writes need a transaction.** The database runs in SQLite's default mode, where every statement outside `BEGIN`/`COMMIT` is its own disk sync. Anything that writes in a loop on the UI isolate (token training in `VerdictController.applyVerdict`, seeding) must wrap the loop in one transaction: a 600-token message took 10.6 s as autocommits and 91 ms in one transaction.

**Drift is declared but not used.** `app/lib/db/tables.dart` is a Drift-style schema with no codegen and no importers; the schema that runs is the `CREATE TABLE IF NOT EXISTS` block in `app/lib/db/database.dart` (it also has `pending_imap_actions`, which `tables.dart` lacks). There is no schema version; `AppDatabase._migrate()` adds missing columns by checking `PRAGMA table_info` (currently `messages.cc_addrs`), so altering an existing table needs a step there. Despite its name, `TokenStoreDrift` is SQLite-backed.

**Search is local first, then the user's mail server.** The Search tab queries `search_index`, an FTS5 table in the same SQLite file, kept current by triggers on `bodies` (`AppDatabase._createSearchIndex`). After a typing pause it also calls `SyncEngine.searchRemote`, which runs an IMAP `SEARCH` per account and *imports* the hits it lacks through `_storeMessage` (the same writer sync uses), so one local query shows everything. It is never sent to the DataFortress backend. Invariants: `searchRemote` runs on the same queue/connection as sync and syncs the account first; in folders sync keeps current (Inbox, Sent, unlabeled) it only imports UIDs at or below the newest stored one, because a higher one would make `fetchNewerThan` skip the mail in between; Junk, Trash, Drafts and virtual folders are not searched (imported mail is unscored). `is:spam` / `is:newsletter` are local verdicts, so they are never sent to the server. Parsing lives in `app/lib/search/search_query.dart` (FTS5 expression, SQL filters and IMAP criteria from one parse). FTS5 rejects implicit AND next to a parenthesised term, so terms are joined with explicit `AND`. A stored-mail write that bypasses `bodies` would leave the index stale.

**Attachments are listed at sync, downloaded on tap.** `_storeMessage` writes names and IMAP part numbers to `attachments` (`extractAttachments`, `app/lib/mail/attachments.dart`); bytes stay on the server until `SyncEngine.downloadAttachment` re-fetches the message and caches the part as a plain file under `<app support>/attachments/<account>/`. Never trust a stored UID for that: mail moved to Junk keeps its old UID, so the copy must match the stored `Message-ID`, with a header search as fallback. Sender-supplied file names go through `safeFileName`, and runnable types (`isRunnableFileName`) are saved, never opened. Sending builds `multipart/mixed` in `buildOutgoingMessage`; total capped by `maxOutgoingAttachmentBytes`. macOS entitlements need `network.client` and `files.user-selected.read-write`.

**OAuth and token refresh.** Google/Microsoft accounts store `auth_oauth_*` keys (token, refresh token, expiry, provider) in the secure store. `AccountRepository.getAuthForAccount` is the only credential read for every caller and refreshes a token that expires within 2 minutes (`OAuthService`, over the shared `df_oauth`); a provider `invalid_grant` throws `ReauthRequiredException` and Settings → Accounts offers Reconnect. macOS uses the iOS client and a custom URL scheme, never the loopback flow (that is Windows/Linux only).

**New-mail notifications.** `SyncEngine.onNewMail` (new, unread, Inbox, not a folder's first fetch, labelled Inbox/ham, score < 0.6) feeds `NewMailNotifier` (`app/lib/notifications/`), which batches by `notify_mode` (`off`, `instant` default, `every5min`, `hourly`; stored in the `settings` table). `AppBootstrap` owns the timers (sync every 60 s in `instant`, else 5 min). Delivery goes through the shared `df_notifications` (`DfReminderService.show`, desktop-capable). Only while the process runs: there is no mobile background fetch.

**Sync serialization.** All account syncs share one IMAP connection; `SyncEngine.syncAccount` queues them and joins duplicate requests per account. Keep that invariant when adding IMAP work. Only the Inbox, unlabeled folders and Sent are synced; Sent (`classify: false`) is never scored, moved to Junk or used for training, and virtual folders (Gmail All Mail etc.) are skipped. Folder listing must stay recursive or nested Sent/Trash folders disappear.

**Platform split.** `AppPlatformServices` (`platform/platform_services.dart`) has two implementations chosen at startup: `native_services.dart` (iOS/Android/macOS: native Firebase Auth + RevenueCat) and `desktop_services.dart` (Windows/Linux: REST Firebase auth, hosted-checkout billing, no-op error sinks). `main.dart` injects the database and services via `ProviderScope` overrides; tests do the same.

**Shared code is defined once.** Tokenizer and fingerprint logic live only in `spam_core`, used by the app and by `train_prior`, so training data and client fingerprints cannot drift apart. Don't duplicate them in the app.

**Auto-unsubscribe flow.** When a user marks a message as spam, `VerdictController` schedules an auto-unsubscribe action after 10 s (buffering the 8 s undo window). `undo()` or any non-spam verdict cancels that message's pending timer (one timer per message); an undo of a ham verdict that restores spam never schedules. `SyncEngine` extracts `List-Unsubscribe`, `List-Unsubscribe-Post`, and parses `Authentication-Results` via `AuthResults.parse` (`sender_auth_pass` = 1 if DMARC or DKIM passes) into SQLite. `UnsubscribeService` executes RFC 8058 One-Click (HTTPS POST) or RFC 2369 mailto. Automated triggers require `isAutoUnsubscribeEnabled` (setting `auto_unsubscribe`, default true) and `sender_auth_pass == 1`. Manual triggers from the reader view bypass only the sender authentication guard. All requests enforce strict guards: `UnsubscribeGuard` validates HTTPS on port 443, rejects localhost/`.local`/`.internal`, pre-resolves DNS, blocks loopback/private/link-local/CGNAT/ULA IPs, and disables redirects; HTTP POST uses plain Dio with generic User-Agent, exact body `List-Unsubscribe=One-Click`, and zero cookies/tokens; mailto enforces single recipient and no header injection without saving to Sent; attempts are rate-capped at 20/24h, deduplicated for 30 days on success, backed off for 24h on failure (max 3 tries), and audited in `unsubscribe_log`. Never contacts the DataFortress backend.

**Privacy invariants** (documented in `docs/concepts/privacy-spec.md`; don't regress): community reports go through a plain unauthenticated `Dio` client with no IDs; no body fingerprint for messages under 40 words; freemail sender domains are never hashed; URLs are normalized and stripped of query/fragment before hashing; remote images are blocked by default; mail credentials live only in the OS secure store; the Pro sync key is never derived from auth credentials; auto-unsubscribe communicates only with sender-published endpoints directly or through the user's SMTP server (never the DataFortress backend) with generic headers, no cookies or device IDs, and strict SSRF and sender-auth verification.

## Conventions

- All user-facing copy goes through `AppStrings` / `UiStrings` (`app/lib/app/`); no literals in widgets.
- Theme comes from `df_theme` via `DfBrandPresets.dataFortress`-based brand in `app/lib/theme/app_brand.dart` ("Ledger Desk": Fraunces / Public Sans / JetBrains Mono, bundled fonts, no runtime Google Fonts). Read colors from `context.df`, not hard-coded values.
- `df_oauth` (sign-in) and `df_notifications` (local notifications) are shared packages added for this; fix shared behavior in `df_flutter_shared` (additive only, consumers track `main`), not in the app.
- `df_*` shared packages already cover many things (settings scaffold, funnel/paywall, billing, analytics); check there before hand-rolling.
- `app/assets/prior_model.json` is a hand-curated seed, not corpus-trained. Don't claim otherwise; never train on TREC data (research-only licence).

## Documentation must be updated with every functionality change

The docs site (`docs/` + `mkdocs.yml`, published to GitHub Pages by `.github/workflows/docs.yml`) is part of the product now that the repo is public. **Any change that adds or alters behavior must update the matching docs in the same change**, not later. Map:

| You changed | Update |
|---|---|
| Filter scoring, signals, classes, training | `docs/concepts/spam-filter.md`, `docs/reference/spam-core-api.md` |
| What is sent off-device, sanitizer, credentials, image handling | `docs/concepts/privacy-model.md`, `docs/concepts/privacy-spec.md` |
| Community report/blocklist flow, PoW | `docs/concepts/community-sharing.md`, `docs/reference/backend-protocol.md` |
| Any HTTP call to the backend (endpoint, payload, status handling) | `docs/reference/backend-protocol.md` |
| Pro features, sync, ONNX, entitlement gating | `docs/concepts/premium.md`, `docs/open-source.md` (free vs Pro table) |
| SQLite tables/columns | `docs/reference/database.md` (and `database.dart` is the truth, not `tables.dart`) |
| `--dart-define` flags, setup steps, platform requirements | `docs/getting-started/*`, `docs/contributing/platform-notes.md` |
| Files/folders added, moved or removed | `docs/reference/project-layout.md` |
| Layers, data flow, new subsystem | `docs/concepts/architecture.md` |
| User-visible feature | the feature list in `README.md` and `docs/index.md` |
| A new page | add it to `nav` in `mkdocs.yml` |

Rules for doc edits: **verify every claim against the code before writing it** — a generated first draft of these docs cited files that don't exist and a database layer that isn't used, so don't copy statements from other doc pages or from this file's older siblings without checking. Link to real paths only. Run `mkdocs build --strict` before finishing. Docs describe the client and the protocol only, never backend internals. Update this `CLAUDE.md` too when commands or architecture change.
