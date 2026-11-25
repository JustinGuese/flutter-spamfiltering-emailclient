# Configuration & Environment Flags

DataFortress Mail is designed to function as an autonomous, self-contained email client without requiring any backend services, registration keys, or API tokens.

This page documents the compile-time `--dart-define` parameters recognized by the client and explains exactly what functions offline versus what relies on hosted infrastructure.

---

## Environment Variables (`String.fromEnvironment`)

The client codebase defines these compile-time environment flags using `String.fromEnvironment`:

| Variable | File | Default Value | Purpose |
|---|---|---|---|
| `BACKEND_URL` | `app/lib/api/backend_config.dart` (used by `api_client.dart` and `report_client.dart`) | `https://emailprogram-spamfilter-backend-api.datafortress.cloud` (the hosted backend) | Base URL for community blocklist sync, threat reports, and ham dispute votes. |
| `REVENUECAT_API_KEY_IOS` / `REVENUECAT_API_KEY_ANDROID` | `app/lib/platform/native_services.dart` | `""` (empty string) | Public SDK keys (one per store app) for RevenueCat subscription and entitlement management. iOS and macOS share the iOS key. `REVENUECAT_API_KEY` is still read as a single fallback for both. |
| `FIREBASE_API_KEY_ANDROID` / `FIREBASE_API_KEY_IOS` (or the single fallback `FIREBASE_API_KEY`) | `app/lib/platform/firebase_options_from_env.dart` | `""` | Firebase Web API key used for native `FirebaseOptions` initialization. |
| `FIREBASE_APP_ID_ANDROID` | `app/lib/platform/firebase_options_from_env.dart` | `""` | Firebase application ID for Android (e.g. `1:801199434424:android:...`). |
| `FIREBASE_APP_ID_IOS` | `app/lib/platform/firebase_options_from_env.dart` | `""` | Firebase application ID for iOS and macOS (e.g. `1:801199434424:ios:...`). |
| `FIREBASE_PROJECT_ID` | `app/lib/platform/firebase_options_from_env.dart` | `""` | Firebase project ID (e.g. `datafortress-mail`). |
| `FIREBASE_MESSAGING_SENDER_ID` | `app/lib/platform/firebase_options_from_env.dart` | `""` | Firebase Cloud Messaging sender ID / project number. |
| `FIREBASE_AUTH_DOMAIN` | `app/lib/platform/firebase_options_from_env.dart` | `""` | Firebase Auth domain (e.g. `datafortress-mail.firebaseapp.com`). |
| `FIREBASE_WEB_API_KEY` | `app/lib/platform/desktop_services.dart` | `""` | Firebase Web API key used for desktop REST authentication on Windows and Linux via `df_firebase_rest`. |
| `RC_WEB_PURCHASE_LINK` | `app/lib/platform/desktop_services.dart` | `""` | Base URL for the RevenueCat Web Purchase Link (e.g. `https://pay.rev.cat/<token>/`), opened with the user's UID on desktop. |
| `RC_WEB_PUBLIC_API_KEY` | `app/lib/platform/desktop_services.dart` | `""` | RevenueCat Web Billing public API key used by desktop client to query subscriber entitlement via REST. |
| `GOOGLE_OAUTH_CLIENT_ID_IOS` | `app/lib/mail/oauth/oauth_config.dart` | `""` | Google OAuth client ID used on iOS **and macOS**. |
| `GOOGLE_OAUTH_CLIENT_ID_ANDROID` | `app/lib/mail/oauth/oauth_config.dart` | `""` | Google OAuth client ID used on Android. |
| `GOOGLE_OAUTH_CLIENT_ID_DESKTOP` | `app/lib/mail/oauth/oauth_config.dart` | `""` | Google OAuth client ID used on Windows and Linux. |
| `GOOGLE_OAUTH_CLIENT_SECRET_DESKTOP` | `app/lib/mail/oauth/oauth_config.dart` | `""` | The (non-confidential) secret Google issues with a Desktop-type client; sent only on Windows and Linux. |
| `MS_OAUTH_CLIENT_ID` | `app/lib/mail/oauth/oauth_config.dart` | `""` | Microsoft (Entra) application client ID, used on every platform. |

### 1. `BACKEND_URL`
- **Location**: `app/lib/api/backend_config.dart`, defined once and read by both the authenticated client and the anonymous community client.
- **When unset**: Defaults to the hosted backend, `https://emailprogram-spamfilter-backend-api.datafortress.cloud`. Community blocklist sync and anonymous spam reporting are therefore live in a default build (reporting can be switched off under Settings → Privacy).
- **Behavior**:
  - The application periodically requests blocklist snapshots from `/v1/blocklist/snapshot` and deltas from `/v1/blocklist/delta`.
  - When the user manually flags spam or rescues ham, anonymous fingerprint payloads are posted to `/v1/reports` and `/v1/votes/ham`.
  - If the backend is unreachable (offline, or a custom URL with no server), all network requests fail gracefully with logged exceptions (`[community report]`, `[community snapshot]`).
  - **No UI errors or crashes occur.** Local mail retrieval and on-device spam filtering proceed unhindered.
- **Customization**:
  ```bash
  flutter run -d linux --dart-define=BACKEND_URL=http://localhost:8000   # e.g. a backend you run locally
  ```

### 2. Firebase & RevenueCat Pro-Auth Configuration

DataFortress Pro features (multi-device filter sync and premium entitlements) require user authentication and subscription management. The free email client and local Bayesian filter **never require an account or these keys**.

Because the repository is open source, Firebase is initialized from compile-time `--dart-define` parameters rather than committed `google-services.json` or `GoogleService-Info.plist` files.

#### Native Defines (iOS, Android, macOS)
- `FIREBASE_API_KEY_ANDROID` / `FIREBASE_API_KEY_IOS`: the API key of each platform app in your Firebase project (iOS and macOS share the iOS app). `FIREBASE_API_KEY` is read as a single fallback for both.
- `FIREBASE_APP_ID_ANDROID`: Android App ID (e.g., `1:801199434424:android:...`).
- `FIREBASE_APP_ID_IOS`: iOS and macOS App ID (e.g., `1:801199434424:ios:...`).
- `FIREBASE_PROJECT_ID`: The Firebase project identifier (e.g., `datafortress-mail`).
- `FIREBASE_MESSAGING_SENDER_ID`: Project number / sender ID.
- `FIREBASE_AUTH_DOMAIN`: Auth domain (e.g., `datafortress-mail.firebaseapp.com`).
- `REVENUECAT_API_KEY_IOS` / `REVENUECAT_API_KEY_ANDROID`: Public SDK keys for App Store and Google Play billing.

On native platforms, `NativePlatformServices` constructs a `FirebaseOptions` object from these flags and initializes Firebase Auth. When a user logs in, their Firebase UID is registered with RevenueCat (`DfRevenueCat.logIn(uid)`).

#### Desktop Defines (Windows, Linux)
Desktop platforms bypass store SDKs and native Firebase binaries entirely, using HTTP REST APIs:
- `FIREBASE_WEB_API_KEY`: Used by `df_firebase_rest` to authenticate users via Firebase Auth REST endpoints.
- `RC_WEB_PURCHASE_LINK`: The base URL of your RevenueCat Web Purchase Link (hosted Stripe checkout, e.g., `https://pay.rev.cat/<token>/`). When upgrading, the app appends the user's percent-encoded Firebase UID and opens this link in the default browser.
- `RC_WEB_PUBLIC_API_KEY`: Public key used by `dfFetchRevenueCatEntitlement` to query RevenueCat's REST endpoint (`GET /v1/subscribers/{uid}`) when the desktop app resumes, checking if the `pro` entitlement is active.

#### Defining Billing Keys Locally (`billing.defines.json`)
Copy `app/billing.defines.example.json` to `app/billing.defines.json` (gitignored, never commit real keys):
```json
{
  "REVENUECAT_API_KEY_IOS": "appl_your_revenuecat_ios_macos_public_sdk_key",
  "REVENUECAT_API_KEY_ANDROID": "goog_your_revenuecat_android_public_sdk_key",
  "FIREBASE_API_KEY_ANDROID": "your_firebase_android_api_key",
  "FIREBASE_API_KEY_IOS": "your_firebase_ios_api_key",
  "FIREBASE_APP_ID_ANDROID": "1:000000000000:android:0000000000000000000000",
  "FIREBASE_APP_ID_IOS": "1:000000000000:ios:0000000000000000000000",
  "FIREBASE_PROJECT_ID": "your_firebase_project_id",
  "FIREBASE_MESSAGING_SENDER_ID": "000000000000",
  "FIREBASE_AUTH_DOMAIN": "your_project.firebaseapp.com",
  "FIREBASE_WEB_API_KEY": "your_firebase_web_api_key",
  "RC_WEB_PURCHASE_LINK": "https://pay.rev.cat/your_token/",
  "RC_WEB_PUBLIC_API_KEY": "rcb_your_revenuecat_web_public_key"
}
```
Run with:
```bash
flutter run -d macos --dart-define-from-file=billing.defines.json
flutter run -d linux --dart-define-from-file=billing.defines.json
```

#### Behavior When Unconfigured
- If Firebase defines are missing, the app functions normally without errors.
- The Settings → Account tile is hidden.
- Tapping **Upgrade to Pro** informs the user that checkout is unavailable in this build (`UiStrings.checkoutUnavailable`).

---

### 3. OAuth client IDs (Google and Microsoft sign-in)
- **Location**: `app/lib/mail/oauth/oauth_config.dart`. The PKCE exchange, token refresh and the interactive flows come from the shared `df_oauth` package; this file only supplies the mail scopes, client IDs and redirect URIs.
- **When unset**: The "Continue with Google" and "Continue with Microsoft" buttons in the account wizard stay visible. Tapping one for a provider whose client ID is empty shows "Google sign-in is not configured in this build" (or the Microsoft equivalent) instead of starting a flow. Password accounts are unaffected.
- **Scopes requested**:
  - Google: `https://mail.google.com/`, `openid`, `email`, `profile`.
  - Microsoft (authority `common`, so personal and work/school accounts): `https://outlook.office.com/IMAP.AccessAsUser.All`, `https://outlook.office.com/SMTP.Send`, `offline_access`, `openid`, `email`, `profile`.
- **Redirect URIs to register** (the application ID / bundle ID is `com.datafortress.spamfilteringemailclient`):

  | Platform | Google | Microsoft |
  |---|---|---|
  | Android | `com.datafortress.spamfilteringemailclient:/oauth2redirect` | `msauth://com.datafortress.spamfilteringemailclient/oauth2redirect` |
  | iOS and macOS | the reversed client ID, e.g. `com.googleusercontent.apps.<id>:/oauth2redirect` | `msauth.com.datafortress.spamfilteringemailclient://auth` |
  | Windows and Linux | `http://127.0.0.1` (loopback, random port chosen at sign-in) | `http://127.0.0.1` (loopback, random port chosen at sign-in) |

  On iOS and macOS the reversed-client-ID scheme must also be listed under `CFBundleURLSchemes` in `Info.plist`; see [Platform notes](../contributing/platform-notes.md#oauth-sign-in-and-notifications-per-platform).
- **Provider-side requirements** (outside this repo): Google classifies `https://mail.google.com/` as a restricted scope, so a public release needs Google's app verification; until then the consent screen is limited to test users and refresh tokens are short-lived. Many Microsoft work or school tenants disable IMAP or SMTP AUTH, in which case only personal outlook.com, hotmail and live accounts connect.
- **Local values**: copy `app/oauth.defines.example.json` to `app/oauth.defines.json` (gitignored, never commit it) and fill in your own client IDs. Build with `flutter run --dart-define-from-file=oauth.defines.json`. In CI, pass the IDs and `GOOGLE_OAUTH_CLIENT_SECRET_DESKTOP` as `--dart-define` values from repository secrets. Android debug builds need a client registered with the debug keystore's SHA-1 in `GOOGLE_OAUTH_CLIENT_ID_ANDROID`.  How to register the clients: [OAuth Setup](../contributing/oauth-setup.md).
- **Customization**:
  ```bash
  flutter run -d linux \
    --dart-define=GOOGLE_OAUTH_CLIENT_ID_DESKTOP=<id>.apps.googleusercontent.com \
    --dart-define=GOOGLE_OAUTH_CLIENT_SECRET_DESKTOP=<desktop-client-secret> \
    --dart-define=MS_OAUTH_CLIENT_ID=<application-client-id>
  ```

---

## Operational Capabilities Matrix

The following table details what works out-of-the-box with zero keys and no backend versus features that depend on hosted services:

| Feature Area | Works Offline / No Backend | Requires Hosted Backend or API Keys |
|---|---|---|
| **Email Accounts (IMAP/SMTP)** | **Yes.** Full connection to any standard IMAP/SMTP provider (Gmail, Outlook, iCloud, Fastmail, self-hosted) with a password or app password. | None. |
| **Google / Microsoft sign-in (OAuth2)** | **Yes, once client IDs are compiled in.** Talks only to Google and Microsoft, never to the DataFortress backend. | The OAuth client IDs above (a build without them shows "not configured" on tap). |
| **New-mail notifications** | **Yes.** Local notifications raised on the device while the app is running. | None. |
| **Email Viewing & Sync** | **Yes.** Periodic folder sync, UID tracking, body fetching, attachments, HTML sanitization, and remote image blocking. | None. |
| **Email Composition** | **Yes.** Plain-text composing with Cc/Bcc, Reply / Reply All / Forward (quoted text, `In-Reply-To`/`References` threading headers), and SMTP transmission via `enough_mail`. Attachments in both directions: attach files while writing (up to 18 MB in total), and forwards carry the original's files. | None. |
| **Local Bayesian Spam Filter** | **Yes.** Full Robinson-Fisher chi-squared classification based on `packages/spam_core`. | None. |
| **Cold Start Prior** | **Yes.** Seeds initial weights using the local asset `app/assets/prior_model.json`. | None. |
| **Filter Retraining** | **Yes.** Changing verdicts in the Verdict Bar immediately updates local SQLite token counts. | None. |
| **Evidence Sheet** | **Yes.** Explains token probabilities and SPF/DKIM/DMARC authentication results locally. | None. |
| **Secure Storage** | **Yes.** Credentials encrypted in native platform hardware keystore (`flutter_secure_storage`). | None. |
| **Community Blocklist Sync** | **No.** Cannot download global fingerprint lists without a reachable community backend. | Requires `BACKEND_URL` serving `/v1/blocklist/*`. |
| **Anonymous Spam Reporting** | **No.** Local MinHash LSH and URL hashes are not broadcast without a reachable backend. | Requires `BACKEND_URL` serving `/v1/reports`. |
| **Ham Dispute Votes** | **No.** False positive rescues cannot be broadcast without a reachable backend. | Requires `BACKEND_URL` serving `/v1/votes/ham`. |
| **Pro Encrypted Filter Sync** | **No.** Synchronizing trained tokens across devices requires Firebase Auth and backend sync endpoint. | Requires `BACKEND_URL` and Firebase Auth (`FIREBASE_*` defines). |
| **Pro Subscriptions** | **No.** In-app purchases, web checkout, and receipt validation require RevenueCat and Firebase Auth. | Requires `REVENUECAT_API_KEY_IOS` / `_ANDROID` (native) or `RC_WEB_PURCHASE_LINK` + `RC_WEB_PUBLIC_API_KEY` (desktop), plus Firebase Auth. |

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

![Onboarding Flow](../assets/screenshots/onboarding_page1.png)

![Connect Account Dialog](../assets/screenshots/connect_account.png)
