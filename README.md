<p align="center">
  <img src="logo.png" alt="DataFortress Logo" width="180">
</p>

# DataFortress

DataFortress is a privacy-first, editorial desktop and mobile email client engineered for focus, local intelligence, and collective defense. Built with Flutter and a pure Dart Bayesian engine, it classifies incoming mail directly on your device, blocking trackers and spam while ensuring personal messages and credentials never leave your hardware.

---

## Features

- **"The Ledger Desk" Design**: Restrained ink-on-paper aesthetic with responsive adaptive layouts (single stack, two-pane, three-pane) and list density toggles. Includes bundled typography (Fraunces, Public Sans, JetBrains Mono) with zero runtime Google Fonts network calls.
- **Transparent Local Spam Filter**: Local Robinson-Fisher Bayesian analysis with 3-way classification (Inbox · Newsletter · Spam) and an interactive Evidence Sheet that details exact token weights, SPF/DKIM/DMARC authentication signals, and heuristic flags.
- **Privacy-First Architecture**: Aggressive client-side HTML sanitization (strips scripts, forms, and inline styles), remote image blocking by default with per-sender overrides, and hardware-backed credential storage via OS keychains.
- **Anonymous Collective Defense**: Zero-ID spam and ham reporting using privacy-preserving MinHash LSH fingerprinting and hash proof-of-work—no user identifiers, tokens, or email bodies are ever transmitted.
- **Open-Core Model**: The client application and core `spam_core` engine are fully open source. Hosted community reputation aggregation and encrypted sync services represent commercial extensions.

---

## Quickstart

```bash
git clone https://github.com/JustinGuese/flutter-spamfiltering-emailclient.git
cd flutter-spamfiltering-emailclient/app
flutter pub get
flutter run
```

---

## Documentation

Comprehensive documentation covering installation, configuration, filter architecture, privacy models, and contribution guidelines is available in the [`docs/`](docs/index.md) directory.

---

## License

DataFortress is licensed under the [Apache License, Version 2.0](LICENSE). See [NOTICE](NOTICE) for trademark restrictions and bundled third-party font notices.

Under our open-core model, the email client and filtering engine are open source, while hosted collective reputation and sync services are proprietary.
