# Contributing to DataFortress Mail

Thank you for your interest in contributing to DataFortress Mail. This document outlines the developer environment setup, coding guidelines, repository layout, and pull request workflow.

For the project's licensing model and open-core breakdown, see the [Open-Core Overview](../open-source.md). For platform-specific compilation details, see the [Platform Notes](platform-notes.md). To enable Google and Microsoft sign-in in your own build or fork, see [OAuth Setup](oauth-setup.md).

---

## Development Environment Setup

### Prerequisites

- **Flutter SDK**: a release that bundles Dart `^3.12.0` (developed against Flutter 3.50 stable)
- **Dart SDK**: `^3.12.0` (bundled with Flutter)
- **Git**
- Platform-specific build tools:
  - **Linux**: `clang`, `cmake`, `ninja-build`, `pkg-config`, `libgtk-3-dev`, `libsecret-1-dev`, `gnome-keyring`
  - **macOS**: Xcode with Command Line Tools, CocoaPods
  - **Windows**: Visual Studio 2022 with "Desktop development with C++"
  - **Android**: Android Studio / Android SDK, JDK 17
  - **iOS**: macOS host with Xcode and CocoaPods

### Repository Setup

Clone the repository and fetch dependencies for both the app and auxiliary packages:

```bash
git clone https://github.com/JustinGuese/flutter-emailprogram-spamfilter.git
cd flutter-emailprogram-spamfilter

# Fetch dependencies for the standalone spam engine
cd packages/spam_core
dart pub get

# Fetch dependencies for the offline prior trainer
cd ../../tools/train_prior
dart pub get

# Fetch dependencies for the Flutter client
cd ../../app
flutter pub get
```

### Local Overrides for `df_flutter_shared`

The application depends on `df_flutter_shared` modules (`df_theme`, `df_ui_widgets`, etc.) via Git. If you are developing features across both repositories simultaneously, create a local `app/pubspec_overrides.yaml` file (which is excluded from Git tracking):

```yaml
dependency_overrides:
  df_theme:
    path: /path/to/local/df_flutter_shared/df_theme
  df_ui_widgets:
    path: /path/to/local/df_flutter_shared/df_ui_widgets
  df_onboarding:
    path: /path/to/local/df_flutter_shared/df_onboarding
  df_funnel:
    path: /path/to/local/df_flutter_shared/df_funnel
  df_settings:
    path: /path/to/local/df_flutter_shared/df_settings
  df_billing:
    path: /path/to/local/df_flutter_shared/df_billing
  df_revenuecat:
    path: /path/to/local/df_flutter_shared/df_revenuecat
```

Do not commit overrides to version control.

---

## Development Loop

### Running the App

Run the debug build on your target platform from the `app/` directory:

```bash
cd app
flutter run -d linux      # or macos, windows, chrome, android, ios
```

On Linux systems running Wayland where GTK rendering or keyrings encounter issues, invoke with:

```bash
GDK_BACKEND=x11 flutter run -d linux
```

### Code Formatting and Analysis

All code must pass static analysis and formatting before submitting a pull request:

```bash
# Check formatting
dart format --output=none --set-exit-if-changed .

# Run static analysis
cd app && flutter analyze
cd ../packages/spam_core && dart analyze
cd ../../tools/train_prior && dart analyze
```

### Running Tests

Run the unit and widget test suites across the project:

```bash
# Test the pure Dart Bayesian spam core
cd packages/spam_core
dart test

# Test the Flutter client application
cd ../../app
flutter test
```

---

## Code Style & Architectural Rules

### 1. Centralized UI Copy

**No hardcoded string literals are permitted in UI widgets.**

- General application copy (navigation, mailboxes, verdicts, evidence labels) belongs in `app/lib/app/strings.dart` under `AppStrings`.
- Specialized view copy (reader empty states, onboarding badges, redesign surfaces) belongs in `app/lib/app/ui_strings.dart` under `UiStrings`.

```dart
// Prohibited:
Text('Possible spam — your call')

// Required:
Text(UiStrings.ledgerPossible)
```

### 2. Design System Tokens & Color Usage

**No hardcoded colors (`Colors.red`, `Color(0xFF...)`) are permitted outside the theme definition.**

- UI styling relies on `df_theme` tokens accessed through `context.df.colors` and `AppType`.
- Classification indicators use the semantic helpers in `AppTheme.classificationColor(context, label)`.
- For full typographic standards and color rules, read the [Design System Guide](design-system.md).

### 3. Layer Separation

Keep platform bindings, business logic, and database access clean and decoupled:

- Native system calls must route through the `PlatformService` interface in `app/lib/platform/`.
- Local email storage and filter state are managed via SQLite in `app/lib/db/`.
- Bayesian classification and token extraction are strictly isolated inside `packages/spam_core/`. The core has zero Flutter dependencies.

---

## Where Things Go (Code Map)

| Directory | Purpose |
| --- | --- |
| `app/lib/app/` | Application bootstrap, routing, and centralized copy (`strings.dart`, `ui_strings.dart`). |
| `app/lib/theme/` | "The Ledger Desk" brand configuration (`app_brand.dart`), type system (`app_type.dart`), and palette helpers (`app_theme.dart`). |
| `app/lib/db/` | SQLite database setup and connection lifecycle (`database.dart`). |
| `app/lib/mail/` | IMAP/SMTP client wrappers (`enough_mail`), HTML body sanitizer (`html_sanitizer.dart`), and background sync. |
| `app/lib/filter/` | Token store integration, cold-start model loader, and 3-way verdict state coordinator. |
| `app/lib/community/` | Anonymous zero-ID report client, cryptographic PoW solver, and blocklist synchronization. |
| `app/lib/platform/` | Abstraction layers separating desktop and native mobile capabilities. |
| `app/lib/premium/` | Pro features: E2EE filter synchronization (AES-GCM + CRDT PN-counters) and ONNX neural scorer. |
| `app/lib/ui/` | Mailbox list, email reader, composer, VerdictBar, and EvidenceSheet widgets. |
| `packages/spam_core/` | Standalone pure-Dart classification engine (Bayes, MinHash, tokenizers, URL normalization). |
| `tools/train_prior/` | Offline CLI tool to generate bundled `prior_model.json` assets from raw email corpora. |
| `docs/` | MkDocs documentation site source. |

---

## Pull Request Workflow

1. **Create a topic branch**: Branch off `main` with a descriptive name (e.g., `git checkout -b feature/sanitizer-svg-filter`).
2. **Commit changes**: Write clear, imperative commit messages describing the rationale for the change.
3. **Verify checks**: Ensure `dart format`, `flutter analyze`, and `flutter test` pass cleanly.
4. **Licensing**: All contributions submitted to this repository are licensed under the Apache License 2.0 (inbound equals outbound). No Developer Certificate of Origin (DCO) or Contributor License Agreement (CLA) signature is required.
5. **Open a Pull Request**: Provide a concise summary of changes, references to any relevant issues, and verification notes.
