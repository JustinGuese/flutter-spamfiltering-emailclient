<p align="center">
  <img src="logo.png" alt="DataFortress Logo" width="180">
</p>

# DataFortress

**An email client whose spam filter you can read, train and audit.**

<p align="center">
  <a href="https://justinguese.github.io/flutter-spamfiltering-emailclient/"><b>Documentation</b></a> ·
  <a href="https://justinguese.github.io/flutter-spamfiltering-emailclient/getting-started/install/">Get started</a> ·
  <a href="https://justinguese.github.io/flutter-spamfiltering-emailclient/concepts/privacy-model/">Privacy model</a>
</p>

Most spam filters are black boxes that live on someone else's server, which means your mail has to pass through someone else's cloud first. DataFortress is a Flutter IMAP/SMTP client for iOS, Android, macOS, Windows and Linux that does the filtering on your device instead. A Robinson-Fisher Bayes classifier, SPF/DKIM/DMARC signals and link heuristics produce a score, and the Evidence Sheet shows the exact tokens behind every verdict. One tap on Inbox, Newsletter or Spam trains the filter.

Collective defense works without identifying anyone. Clients share MinHash fingerprints and URL hashes behind a hashcash proof-of-work, with no user ID, no device ID and never any message content. The engine is a standalone pure-Dart package (`spam_core`) that you can use in your own project.

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

Full documentation is published at **<https://justinguese.github.io/flutter-spamfiltering-emailclient/>**. It covers installation, configuration, filter architecture, the privacy model, the backend protocol and contribution guidelines. The sources live in [`docs/`](docs/index.md).

---

## License

DataFortress is licensed under the [Apache License, Version 2.0](LICENSE). See [NOTICE](NOTICE) for trademark restrictions and bundled third-party font notices.

Under our open-core model, the email client and filtering engine are open source, while hosted collective reputation and sync services are proprietary.
