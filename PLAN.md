# Plan: Flutter email client (IMAP/SMTP) + learning spam filter + anonymous community sharing

## Context
This is a greenfield project. `/home/jguese/code/flutter-emailprogram-spamfilter` holds only `.vscode/` and is not a git repo yet.

**Goal:** a basic Outlook-like mail client for iOS, Android, Windows, Linux and macOS. For now it speaks IMAP/SMTP only; Gmail comes later. It adds a learning spam filter on top:
- Spam / Newsletter / Inbox buttons that train it.
- Anonymous global sharing of spam fingerprints.
- A premium tier: filter sync across devices, and an advanced on-device AI model.

Reuse `../df_flutter_shared` where it fits, and keep the app basic.

**Decisions so far:**
- **Backend:** FastAPI + Postgres on the existing k8s/ske stack.
- **Community sharing:** on by default, disclosed in the app, with an off switch. It is live, not a dry run.
- **Classes:** three of them: Spam, Newsletter/Promo, Inbox.
- **Premium:** Sync my filter, plus the Advanced AI model.
- **Funnel:** `df_funnel` handles onboarding, login and upsell, and every step is optional. Mail, the local filter and community sharing all work without login.

---

## Research answers (your questions)

### Is Bayes state of the art?
No, but it is still the right core for this app.

**What large providers run.** Gmail, Microsoft and rspamd run layered ensembles:
1. Sender authentication: SPF/DKIM/DMARC.
2. IP, domain and URL reputation lists.
3. Collaborative fuzzy fingerprints (DCC, Razor, Pyzor, rspamd fuzzy storage). This is the "share hashes" idea, and it is proven.
4. Neural content models (Gmail's RETVec, BERT/DeBERTa-class transformers).
5. User-feedback loops.
6. Increasingly, LLMs for phishing and business-email compromise.

**How the content models compare.**
- On public benchmarks, transformers reach about 99% accuracy. Naive Bayes trails by roughly 1–2 points (for example 97.2% vs 98.5% in one 2025 phishing study).
- Naive Bayes loses about 5 points against spam that an LLM has rephrased.
- Hybrid NB + DeBERTa beats either one alone.
- The public datasets are old, so headline numbers flatter everyone.

**Why Bayes fits here.** A Bayes filter is per-user, trains instantly from one click, needs a tiny model and runs everywhere. It is the only layer that learns your own idea of what "newsletter" means.

**The design that follows.**
- **Free:** Bayes + auth headers + heuristics + community fingerprints.
- **Premium:** adds a small transformer model, combined with the rest by a hybrid score.

### Public lists and data (licences must be checked before shipping)

**URL and domain reputation**
- **URLhaus (abuse.ch):** open feed. Ingest it on the backend.
- **OpenPhish community** and **PhishTank:** free, registration may be required, commercial terms to be checked.
- **Spamhaus ZEN/DBL/HBL, SURBL, URIBL:** commercial or high-volume use needs a paid licence (Spamhaus DQS). Spamhaus blocks queries from resolvers that can't be attributed. **Never query DNSBLs from end-user devices.** If used at all, they are a backend premium feed later.
- **Google Safe Browsing:** non-commercial only. The commercial equivalent is Web Risk, which is paid.

**Domain lists**
- The `disposable-email-domains` list (CC0).
- A freemail domain list, so freemail domains are never used as sender-reputation keys.
- The Tranco top-sites list, used as a guard against poisoning popular domains.

**Training corpora for the shipped prior model**
- SpamAssassin public corpus and Enron-Spam: widely used. Check the licence.
- TREC 2005–07: research-only licence, so **don't ship models trained on it**.
- Nazario phishing corpus.

**Free signal the provider already gives us.** The `Authentication-Results` header added by the user's own provider carries SPF/DKIM/DMARC verdicts. Use the topmost header that matches the account's provider `authserv-id`.

---

## Architecture

```
flutter-emailprogram-spamfilter/          (git init; monorepo)
  app/                 Flutter app (5 platforms)
  packages/spam_core/  pure-Dart: tokenizer, Bayes, fingerprints, scoring (no Flutter dep)
  tools/train_prior/   Dart CLI: train prior model + evaluate on corpora (uses spam_core)
  backend/             FastAPI + SQLModel + Postgres, k8s manifests, ske config
```

`spam_core` is pure Dart. That lets the app, the prior-training CLI and the tests share one tokenizer and fingerprint implementation, so the fingerprints never drift between client and training.

### App stack (new dependencies; the shared repo has no mail or database layer)
| Concern | Choice |
|---|---|
| IMAP/SMTP/MIME, autodiscover | `enough_mail` (MPL-2.0, pure Dart). The maintenance fork `enough_mail_plus` is the fallback; check the most recent releases at scaffold time. |
| Local DB + search | `drift` + `sqlite3_flutter_libs`, using FTS5 for search |
| Credentials | `flutter_secure_storage` (Linux needs libsecret) |
| HTML mail | `flutter_widget_from_html_core`: pure Flutter on all 5 platforms. Sanitise first (strip script/style/forms). **Block remote images by default** (no tracking pixels), with a "Load images" button. |
| State | `flutter_riverpod` (as in the shared repo) |
| Crypto (sync) | `cryptography` (AES-GCM, HKDF) |
| On-device model (premium) | `fonnx` or `flutter_onnxruntime`. fonnx's July 2026 changelog lists all five platforms but has dropped Intel macOS. Pick one during Phase 4 after a smoke test on all five. |

### Reuse from `../df_flutter_shared`
Add each package as a git dependency (`path: df_x`, `ref: main`). Local development uses a gitignored `pubspec_overrides.yaml`. Per the rule, never commit `../` paths.

- **`df_theme`:** `DfBrandPresets.dataFortress` → app `app_brand.dart` → `DfTheme.light/dark`.
- **`df_app_shell`:**
  - `DfNavShell` gives the bottom bar on phones and the side rail on desktop. Destinations: Mail, Search, Settings.
  - Also use `DfThemeModeController` and `sharedPreferencesProvider`.
- **`df_settings`:** `DfSettingsScaffold/Group/Tile`, theme/locale tiles, `DfLegalLinksSection`, `DfVersionFooter`, `DfDeleteAccountTile`.
- **`df_ui_widgets`:** loading, empty, error and snackbar widgets; `DfFilterChipBar` for the Inbox/Newsletter/Spam tabs.
- **`df_funnel`:**
  - `DfLaunchGate` with `DfFunnelConfig(steps: [onboarding, paywall, login], loginMode: DfLoginMode.optional, paywallSkippable: true)`. Every step can be skipped.
  - `DfPremiumGate` / `requirePremium()` / `DfUpsellSheet` / `DfProPill` on premium entry points.
  - `DfSubscriptionSettingsSection` in settings.
- **`df_onboarding`:** 3 pages (privacy-first client, learning filter, community protection).
- **`df_firebase_auth`** for iOS/Android/macOS; **`df_firebase_rest`** for Windows/Linux (email and password only).
- **`df_revenuecat`** for iOS/Android/macOS; **`df_billing`** (hosted Stripe checkout via the funnel API) for Windows/Linux.
- **`df_error_reporting`:** `NoopErrorSink` on Windows/Linux; `df_error_reporting_firebase` on mobile/macOS.
- **`df_analytics_core`** for funnel events. Firebase Analytics only on mobile.
- **`df_file_download`** for saving attachments; **`df_core_utils`** for date formatting.
- **`df_api`:**
  - `DfApiClient` for the **authenticated** backend channel only.
  - Override `apiClientProvider` so it sends `user.getIdToken()`. By default the shared `ApiClient` sends the bare uid as the token (`df_firebase_auth/lib/src/api_client.dart:28-30`).

**Desktop platform split (Windows/Linux), app-side.** `df_funnel` imports `firebase_auth` and `df_revenuecat`, and `dfEffectivePremiumProvider` watches `currentUserProvider` and `dfRevenueCatIsProProvider`. On Windows/Linux the app therefore:
1. Doesn't call `DfRevenueCat.initialize` or the native Firebase Auth.
2. Overrides `currentUserProvider` to null, `authStateChangesProvider` to `Stream.value(null)` and `dfRevenueCatIsProProvider` to false.
3. Overrides `dfEffectivePremiumProvider` with an app provider: `FirebaseRestAuth` signed in AND backend entitlement.
4. Passes a custom `loginBuilder`, backed by `df_firebase_rest`, and a `paywallPresenter`, backed by `DfCheckout`, to `DfLaunchGate`.

All of this lives in `app/lib/platform/` behind one `AppPlatformServices` facade.

**Small shared-repo PR (separate step):**
- `DfRevenueCatConfig.apiKey` returns the Android key on macOS (`df_revenuecat/lib/src/revenuecat_config.dart:41-46`). Add `macosApiKey`.
- Guard `googleSignInProvider` to the platforms it supports.

**Entitlement is unified by uid in our backend.**
- The RevenueCat webhook and the funnel-API Stripe `entitlement.updated` webhook both feed it, so a phone purchase unlocks the desktop and vice versa.
- RevenueCat `appUserID` = Firebase uid.
- On iOS/Android, Advanced AI works without login (anonymous RevenueCat). Sync always needs login.

---

## Mail client scope (v1, deliberately basic)
- **Account setup:**
  - Email + password; server settings via `enough_mail` Discover (Mozilla ISPDB / autoconfig), with a manual fallback form. Multiple accounts.
  - Auth goes through a `MailAuth` seam: `password | oauth2(tokenProvider)` (XOAUTH2/OAUTHBEARER), so Gmail/Microsoft OAuth plug in later.
  - The setup screen says that Microsoft personal accounts need OAuth (coming later) and that Gmail, iCloud and Yahoo need an app password.
- **Folders:** list with IMAP SPECIAL-USE (`\Junk`, `\Sent`, `\Drafts`, `\Trash`, `\Archive`).
- **Message list:**
  - Paging with UID ranges, a local drift cache, and IDLE while the app is in the foreground.
  - Inbox tabs: Inbox / Newsletters / (Spam = Junk folder).
- **Reader:** sanitised HTML, remote images blocked, attachments list (open/save), headers detail view.
- **Compose:** To/Cc/Bcc with address autocomplete from local contacts harvested from mail. Plain text plus minimal rich text. Attachments, signature.
- **Actions:**
  - Reply, Reply all and Forward with quoting.
  - Drafts autosaved to `\Drafts` (APPEND); Sent APPEND unless the server auto-saves.
  - Read/unread, flag, delete (to Trash), archive, move.
- **Search:** local FTS5 over cached mail, plus a server-side IMAP SEARCH fallback.
- **Out of scope for v1:** background sync and push on mobile (the app syncs on open and on resume; desktop syncs while running), calendar, rules UI, threading (later).

**Files (representative):**
- `app/lib/mail/imap_service.dart`, `smtp_service.dart`, `account_repository.dart`, `sync_engine.dart`
- `app/lib/db/database.dart` (drift tables: accounts, folders, messages, bodies, fts, contacts, classifications, tokens)
- `app/lib/ui/{mailbox,reader,compose,account_setup}/`

Keep each file under about 250 lines, per the house rule.

---

## Spam filter (`packages/spam_core`)

### Pipeline (runs on each newly fetched message)
1. **Fetch** headers + BODYSTRUCTURE + the first text part, capped at 64 KB (`BODY.PEEK[...]<0.65536>`).
2. **Normalise:**
   - MIME decode, HTML→text, NFKC + confusables folding, lowercasing.
   - Strip tracking query parameters.
   - **Remove the recipient's own name and address and the greeting line.** This handles personalisation in spam and also helps privacy.
3. **Tokenise:**
   - Body words plus OSB bigrams (rspamd-style).
   - Prefixed header tokens: `subj:`, `from-dom:`, `url-dom:`, `ct:`, `x-mailer:`, `list-unsub:present`.
4. **Classify in two stages:**
   - **Stage A, spam vs not:** Robinson–Fisher χ² combining (SpamBayes/bogofilter style), with an *unsure* band.
   - **Stage B, newsletter vs inbox** (non-spam only): Bayes plus strong header priors (`List-Unsubscribe`, `List-Id`, `Precedence: bulk`, ESP headers).
5. **Combine** with a small fixed logistic layer: Bayes score, auth results (DMARC fail and similar), heuristics (display-name spoofing, link text ≠ href domain, disposable sender domain), a community fingerprint hit, and (premium) the transformer score.

   Weights are fitted offline in `tools/train_prior` and shipped as JSON.
6. **Thresholds:**
   - Spam ≥ 0.9 → move to Junk.
   - 0.6–0.9 → stays in the Inbox with a "possible spam" banner.
   - Tuned so the false-positive rate on the evaluation corpus stays at or below 0.1%.

### Learning
- **Buttons in the reader and the list:**
  - **Spam:** train spam, move to `\Junk`, set the IMAP keyword `$Junk` and clear `$NotJunk`.
  - **Not spam:** train ham, move to INBOX, set `$NotJunk`.
  - **Newsletter:** train stage B.
  - **Inbox:** train stage B as "inbox".
- **Relabelling** un-trains the previous label (the counts are decremented).
- **Implicit learning:**
  - A message that shows up in Junk via another client → train spam, at half weight.
  - A message the user replies to → ham.
  - Train-on-error otherwise.
- **IMAP mapping:**
  - Spam uses the registered keywords `$Junk`/`$NotJunk` plus the `\Junk` folder.
  - Newsletter uses a custom keyword `$Newsletter` when `PERMANENTFLAGS` contains `\*`. Otherwise it is stored only locally, with an optional "move newsletters to folder X" setting.
- **Cold start:** on account add, train on:
  - Up to 500 messages from the existing Junk folder as spam.
  - Inbox mail from correspondents the user has *sent* to (from `\Sent`) as ham.
  - `List-Unsubscribe` mail as newsletter.

  A shipped **prior model** (token probabilities from licence-checked public corpora) applies with a weight that decays as personal training data grows.

### Storage
The drift `tokens` table holds token hash (64-bit), spam/ham/newsletter/inbox counts, and a per-device counter id for sync. Token *text* is never stored, only its hash.

---

## Anonymous community sharing (free, on by default)

### What is shared (only for messages the user marks **Spam**; Newsletter/Inbox labels never leave the device)
- **Body fingerprint:**
  - 32-value MinHash over word 3-shingles of the normalised, de-personalised body, split into **8 LSH bands × 4 rows** and uploaded as 8 band hashes of 64 bits each.
  - Bodies under 40 words get **no** body fingerprint, because short text is low-entropy and that creates both privacy and false-positive risk.
- **URL fingerprints:** SHA-256/64 of `eTLD+1` and of `host + first path segment`. Query strings and high-entropy path segments (per-recipient tokens) are dropped.
- **Sender-domain hash:** SHA-256/64 of the registered From and Return-Path domain, **skipped for freemail domains**. Never local parts, display names, recipients, the subject, Message-ID or exact timestamps.

### Report channel is separate and anonymous
- `POST /v1/reports` and `POST /v1/votes/ham` go through a plain Dio client, **not** `DfApiClient`. They carry no uid, ID token, `df_device_id` or install id.
- **Abuse resistance without identity:**
  - Firebase App Check token on iOS/Android/macOS. It attests the app, not the user.
  - A small hashcash-style proof-of-work on Windows/Linux.
  - Per-IP rate limit held in memory only.
- **Distinct reporters:** the server stores `HMAC(daily_salt, IP /24 or /48)` against the fingerprint id for that day only. The salt is rotated and deleted every 24 h, so sources become unlinkable afterwards. IPs are never persisted, and ingress access logs are off for these routes.
- **Activation (k-anonymity plus anti-poisoning):**
  - A fingerprint becomes *active* only after **K ≥ 3 distinct sources within 7 days** and spam votes > 2 × ham votes.
  - URL or domain fingerprints for Tranco top-10k domains, or freemail domains, never activate.
  - Fingerprints matching a URLhaus entry activate at K = 1.
- **Ham votes:** a client sends "not spam" only for fingerprints **that matched the downloaded active list**. The server rejects unknown fingerprints, so a legitimate private message can never introduce a new hash.
- **Retention:** pending fingerprints are purged after 14 days; active ones expire 90 days after the last report.

### Lookup is private
- Clients **download** the active set:
  - `GET /v1/blocklist/snapshot` plus `GET /v1/blocklist/delta?since=<ver>`.
  - Responses are identical for everyone and CDN-cacheable.
  - Synced every 6 h.
- Matching is done locally. The server never learns which mail a user receives.
- Size estimate: about 100k active entries × 8 B ≈ 1 MB.

### Compliance
- **Data minimisation:** hashes only, spam only, no identifiers.
- **Legal basis drafted as legitimate interest** (GDPR Art. 6(1)(f), Recital 49, network and information security). **This needs legal review before release**, along with ePrivacy Art. 5(3) and the App Store / Play data-safety labels ("data not linked to you").
- **Disclosure:**
  - An onboarding page.
  - A one-time inline notice the first time the user taps **Spam**, with "Learn more" and "Turn off".
  - A settings toggle, "Share spam fingerprints anonymously".
  - A privacy-policy section that documents exactly the payload above.
- **No silent dead switch:** sharing is live by default. The settings screen shows "last report sent / blocklist version + date" so a stalled pipeline is visible.

---

## Premium
Entry points are gated with `DfPremiumGate` / `requirePremium()` and upsold via `DfUpsellSheet` at natural moments: after 20 manual trainings ("sync this to your other devices?"), and on spam that was missed.

### 1. Sync my filter (needs login)
- **End-to-end encrypted:**
  - On the first premium device the app generates a random 256-bit **sync key**, stored in `flutter_secure_storage`.
  - To add another device: scan a QR code shown by an existing device, or type a 24-word recovery code (the desktop path).
  - Firebase login only authorises storage; it **never derives the key**. The server stores opaque blobs.
- **Model:** each device owns its own counter table: a PN-counter CRDT per token-hash × class. Each device uploads its own table, AES-GCM-encrypted and zstd/gzip-compressed, to `PUT /v1/sync/blobs/{device_slot}`. Other devices download all slots and sum them. There are no merge conflicts, and relabelling is a local decrement.
- Synced alongside: the allow/block sender lists and the threshold settings.

### 2. Advanced AI model (on-device)
- **Model:**
  - A small multilingual transformer (MiniLM/DistilBERT-class, int8 ONNX, ~30–60 MB), fine-tuned by us for spam/phishing/newsletter on licence-checked corpora.
  - The base model's licence must allow commercial use (Apache/MIT).
- **Delivery:** downloaded after the entitlement check via `GET /v1/models/advanced`, which returns a signed URL and needs either an ID token or a RevenueCat-anonymous receipt check.
- **Use:** runs on device and feeds its score into the combiner. **No email content leaves the device.**

---

## Backend (`backend/`, FastAPI + SQLModel + Postgres)
Follow `~/.claude/rules/python-sqlmodel.md` and the `env-config-sops` skill for config and secrets. Deploy to k8s.

**Tables:**
- `fingerprint`: id, kind, hash, spam_votes, ham_votes, state, first_seen, last_report, activated_at.
- `fingerprint_source_day`: fp_id, source_hmac, day. Purged daily.
- `blocklist_version`.
- `entitlement`: uid, source (rc|stripe), active, expires_at.
- `sync_blob`: uid, slot, ciphertext, updated_at.

**Routes:**
- Public: `/v1/reports`, `/v1/votes/ham`, `/v1/blocklist/*`.
- Authenticated (Firebase ID token verified with firebase-admin): `/v1/me/entitlement`, `/v1/sync/blobs/*`, `/v1/models/advanced`.
- Webhooks: `/v1/webhooks/revenuecat`, `/v1/webhooks/entitlement`. The latter is the funnel API's signed `entitlement.updated` event from `shared-marketing-email-ecommerce-endpoint`.

**CronJobs:**
- Activate/expire fingerprints and build the snapshot + delta.
- Ingest URLhaus.
- Rotate the daily salt and purge source rows.

---

## Phases
0. **Scaffold:**
   - `git init`, `flutter create --platforms=ios,android,windows,linux,macos app`, the `spam_core` package and the backend skeleton.
   - Shared-package git deps + gitignored overrides; theme/brand; `DfNavShell`; settings skeleton.
   - The `AppPlatformServices` facade with the desktop overrides.
1. **Mail client:** accounts/discover, folders, list/sync/IDLE, reader (sanitised HTML), compose/reply/reply-all/forward/cc/bcc/attachments, drafts/sent, search.
2. **Local filter:** `spam_core` (tokeniser, Bayes A+B, heuristics, auth-results parser, combiner), the buttons, the IMAP keyword/folder mapping, cold start, and `tools/train_prior` + the prior asset.
3. **Community sharing:** fingerprints in `spam_core`, backend report/vote/blocklist + cron, client sync + matching + disclosure UI, deployed live.
4. **Funnel and premium:**
   - `DfLaunchGate` (all steps optional), RevenueCat (mobile/macOS) and `df_billing` (Windows/Linux), backend entitlement + webhooks.
   - The shared-repo PR (macOS RevenueCat key, Google Sign-In guard).
   - E2E filter sync; ONNX runtime choice + advanced model.
5. **Later:**
   - Gmail/Microsoft OAuth via the `MailAuth` seam. Google's restricted `https://mail.google.com/` scope requires an annual CASA security assessment; plan its cost.
   - Gmail API, mobile background fetch/push, threading.

---

## Verification
- **`spam_core` unit tests (`dart test`):**
  - Tokeniser and normaliser fixtures.
  - Bayes maths against hand-computed χ² values.
  - Fingerprint stability (the same spam sent to two different recipient names → same band hashes); no fingerprint below 40 words.
  - Freemail and query strings are dropped.
- **Filter quality:** `tools/train_prior eval` on held-out public corpora reports spam recall, the false-positive rate at the chosen threshold (target ≤ 0.1%) and the newsletter F1. It is re-run on every change to the tokeniser or combiner.
- **Mail integration:**
  - GreenMail or docker-mailserver in Docker locally.
  - A Flutter integration test that adds an account, receives a seeded spam/newsletter/ham set via SMTP, checks auto-classification and Junk moves, presses the buttons, and asserts the `$Junk`/`$NotJunk` keywords on the server. Also covers reply-all/cc/bcc recipients and Sent/Drafts APPEND.
- **Backend (`pytest`):**
  - No activation below K distinct sources.
  - Ham votes rejected for unknown fingerprints.
  - Salt rotation makes sources unlinkable.
  - No IP or user-id column in any table (schema test).
  - Delta-sync correctness; webhook → entitlement.
- **Privacy check:** a test captures the exact report request body and asserts that it holds only the 64-bit hashes listed above, with no plaintext or identifiers.
- **Platforms:**
  - Local `flutter build linux`, plus `flutter build apk` per the `flutter-android-release` skill.
  - `flutter build windows` and `macos` in CI; iOS via Codemagic per the `flutter-ios-codemagic` skill.
  - Manual smoke test on each platform: add account, read, reply, mark spam, open the paywall, skip every funnel step.
