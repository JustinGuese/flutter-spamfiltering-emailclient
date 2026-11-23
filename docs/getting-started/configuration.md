# Configuration & Environment Flags

DataFortress Mail is designed to function as an autonomous, self-contained email client without requiring any backend services, registration keys, or API tokens.

This page documents the compile-time `--dart-define` parameters recognized by the client and explains exactly what functions offline versus what relies on hosted infrastructure.

---

## Environment Variables (`String.fromEnvironment`)

The client codebase defines two compile-time environment flags using `String.fromEnvironment`:

| Variable | File | Default Value | Purpose |
|---|---|---|---|
| `BACKEND_URL` | `app/lib/api/api_client.dart`<br>`app/lib/community/report_client.dart` | `http://localhost:8000` | Base URL for community blocklist sync, threat reports, and ham dispute votes. |
| `REVENUECAT_API_KEY` | `app/lib/platform/native_services.dart` | `""` (empty string) | Public SDK key for RevenueCat subscription and entitlement management. |

### 1. `BACKEND_URL`
- **Location**: `app/lib/api/api_client.dart:10` and `app/lib/community/report_client.dart:15`
- **When unset**: Defaults to `http://localhost:8000`.
- **Behavior**:
  - The application periodically requests blocklist snapshots from `/v1/blocklist/snapshot` and deltas from `/v1/blocklist/delta`.
  - When the user manually flags spam or rescues ham, anonymous fingerprint payloads are posted to `/v1/reports` and `/v1/votes/ham`.
  - If no backend server is listening at the target URL, all network requests fail gracefully with logged exceptions (`[community report]`, `[community snapshot]`).
  - **No UI errors or crashes occur.** Local mail retrieval and on-device spam filtering proceed unhindered.
- **Customization**:
  ```bash
  flutter run -d linux --dart-define=BACKEND_URL=https://api.custom-server.org
  ```

### 2. `REVENUECAT_API_KEY`
- **Location**: `app/lib/platform/native_services.dart:16`
- **When unset**: Defaults to `""` (empty string).
- **Behavior**:
  - When empty, `NativePlatformServices.initialize()` skips calling `DfRevenueCat.initialize()`.
  - The paywall presented in the onboarding funnel remains skippable via "Maybe later".
  - Pro features that require cloud subscription validation are disabled, and the app remains entirely in the free, local tier.
- **Customization**:
  ```bash
  flutter run -d macos --dart-define=REVENUECAT_API_KEY=appl_your_revenuecat_key
  ```

---

## Operational Capabilities Matrix

The following table details what works out-of-the-box with zero keys and no backend versus features that depend on hosted services:

| Feature Area | Works Offline / No Backend | Requires Hosted Backend or API Keys |
|---|---|---|
| **Email Accounts (IMAP/SMTP)** | **Yes.** Full connection to any standard IMAP/SMTP provider (Gmail, Outlook, iCloud, Fastmail, self-hosted). | None. |
| **Email Viewing & Sync** | **Yes.** Periodic folder sync, UID tracking, body fetching, attachments, HTML sanitization, and remote image blocking. | None. |
| **Email Composition** | **Yes.** Draft creation, rich editing, MIME formatting, and SMTP transmission via `enough_mail`. | None. |
| **Local Bayesian Spam Filter** | **Yes.** Full Robinson-Fisher chi-squared classification based on `packages/spam_core`. | None. |
| **Cold Start Prior** | **Yes.** Seeds initial weights using the local asset `app/assets/prior_model.json`. | None. |
| **Filter Retraining** | **Yes.** Changing verdicts in the Verdict Bar immediately updates local Drift SQLite token counts. | None. |
| **Evidence Sheet** | **Yes.** Explains token probabilities and SPF/DKIM/DMARC authentication results locally. | None. |
| **Secure Storage** | **Yes.** Credentials encrypted in native platform hardware keystore (`flutter_secure_storage`). | None. |
| **Community Blocklist Sync** | **No.** Cannot download global fingerprint lists without a reachable community backend. | Requires `BACKEND_URL` serving `/v1/blocklist/*`. |
| **Anonymous Spam Reporting** | **No.** Local MinHash LSH and URL hashes are not broadcast without a reachable backend. | Requires `BACKEND_URL` serving `/v1/reports`. |
| **Ham Dispute Votes** | **No.** False positive rescues cannot be broadcast without a reachable backend. | Requires `BACKEND_URL` serving `/v1/votes/ham`. |
| **Pro Encrypted Filter Sync** | **No.** Synchronizing trained tokens across devices requires Firebase Auth JWT and backend sync endpoint. | Requires `BACKEND_URL` and Firebase Auth. |
| **Pro Subscriptions** | **No.** In-app purchases and receipt validation require RevenueCat. | Requires `REVENUECAT_API_KEY`. |

---

## Funnel & Authentication Configuration

As configured in `app/lib/funnel/funnel_config.dart`:
```dart
static DfFunnelConfig get config => const DfFunnelConfig(
  steps: [
    DfFunnelStep.onboarding,
    DfFunnelStep.paywall,
  ],
  loginMode: DfLoginMode.deferred,
  paywallSkippable: true,
);
```

- **Deferred Login**: Login is not required to use DataFortress Mail. Users proceed directly to "Add Account" to configure IMAP credentials.
- **Skippable Paywall**: The paywall step is completely dismissible without entering payment details or authentication credentials.
