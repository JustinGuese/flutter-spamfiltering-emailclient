# Setting Up Google and Microsoft Sign-In

"Continue with Google" and "Continue with Microsoft" need one OAuth client per provider and platform family. The shipped repo contains **no client IDs**: you register your own and pass them at build time. This page lists what to register so the app's redirects and scopes line up. The values the app expects are defined in [`app/lib/mail/oauth/oauth_config.dart`](https://github.com/JustinGuese/flutter-emailprogram-spamfilter/blob/main/app/lib/mail/oauth/oauth_config.dart).

!!! warning "Keep real values out of git"
    Copy `app/oauth.defines.example.json` to `app/oauth.defines.json`. The real file is gitignored; never commit client IDs or the Desktop secret. In CI pass them as `--dart-define` values from repository secrets.

```bash
cd app
flutter run --dart-define-from-file=oauth.defines.json
```

| Define | Used on |
|---|---|
| `GOOGLE_OAUTH_CLIENT_ID_IOS` | iOS and macOS |
| `GOOGLE_OAUTH_CLIENT_ID_ANDROID` | Android |
| `GOOGLE_OAUTH_CLIENT_ID_DESKTOP`, `GOOGLE_OAUTH_CLIENT_SECRET_DESKTOP` | Windows and Linux |
| `MS_OAUTH_CLIENT_ID` | every platform |

The application ID / bundle ID everywhere below is `com.datafortress.spamfilteringemailclient`.

---

## Redirect URIs

| Platform | Google | Microsoft |
|---|---|---|
| Android | `com.datafortress.spamfilteringemailclient:/oauth2redirect` | `msauth://com.datafortress.spamfilteringemailclient/oauth2redirect` |
| iOS and macOS | reversed client ID, `com.googleusercontent.apps.<id>:/oauth2redirect` | `msauth.com.datafortress.spamfilteringemailclient://auth` |
| Windows and Linux | `http://127.0.0.1` (random port) | `http://127.0.0.1` (random port) |

## Scopes

- Google: `https://mail.google.com/`, `openid`, `email`, `profile`.
- Microsoft (authority `common`): `https://outlook.office.com/IMAP.AccessAsUser.All`, `https://outlook.office.com/SMTP.Send`, `offline_access`, `openid`, `email`, `profile`.

---

## Google (Cloud Console → Google Auth Platform → Clients)

Create the clients in a dedicated Google Cloud project with no billing account attached.

1. **iOS** client: bundle ID `com.datafortress.spamfilteringemailclient`. Its client ID goes in `GOOGLE_OAUTH_CLIENT_ID_IOS` and is also used on macOS. Add the reversed ID `com.googleusercontent.apps.<id>` under `CFBundleURLSchemes` in `app/ios/Runner/Info.plist` and `app/macos/Runner/Info.plist`.
2. **Android** client: package name above plus the **SHA-1** of the signing key. A client takes one SHA-1, so debug builds, the upload key and the Play App Signing key each need their own client; pass the matching ID in `GOOGLE_OAUTH_CLIENT_ID_ANDROID` for that build.
3. **Desktop** client for Windows and Linux. Google issues a secret with it; for an installed app it is not confidential, but keep it out of git anyway.

!!! info "Restricted scope"
    `https://mail.google.com/` is a restricted scope. Until Google verifies the app, sign-in works for at most 100 users and shows an "unverified app" warning. Verification is only needed for a public release; for personal use or a fork you can add yourself as a test user.

## Microsoft (Entra admin center → App registrations)

An Entra tenant is required to register an app; a free Azure account provides one. Registering an app has no usage cost.

1. **New registration**, supported account types **"Accounts in any organizational directory and personal Microsoft accounts"**.
2. Authentication → add platform **Mobile and desktop applications** and add the three redirect URIs: the Android and iOS/macOS values from the table above, and `http://localhost` for Windows and Linux (Microsoft ignores the port on loopback addresses; the app sends `http://127.0.0.1`).
3. Authentication → Settings → enable **Allow public client flows**.
4. Copy the **Application (client) ID** into `MS_OAUTH_CLIENT_ID`.

The IMAP and SMTP scopes are requested at sign-in and the user approves them there; a fresh tenant has no Exchange Online service to pre-select them from. Publisher verification (a free Microsoft Partner Network account plus a domain check) is optional and only removes the "unverified" label.

!!! note "Windows and Linux loopback"
    If a Microsoft sign-in on desktop fails with a redirect mismatch, send `http://localhost` instead of `http://127.0.0.1` from `df_oauth`'s loopback flow.

## Forks

A fork registers its own Google and Microsoft apps and uses its own bundle ID, which changes the Android and Microsoft redirect URIs above (`bundleId` in `oauth_config.dart`, the Android `appAuthRedirectScheme` placeholder, and the iOS/macOS URL types).
