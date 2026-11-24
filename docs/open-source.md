# Open-Source & Licensing Model

DataFortress Mail operates on an **open-core** model. The cross-platform client application, local Bayesian spam classification engine, offline training tools, and protocol specifications are open source under the permissive Apache License 2.0. The hosted community aggregation backend and Pro cloud synchronization services are operated as proprietary infrastructure.

---

## Open-Core Architecture Breakdown

The table below outlines the boundary between open-source components in this repository and external proprietary services:

| Component | Repository Path / Service | License / Distribution | Description |
| --- | --- | --- | --- |
| **Flutter Client** | `app/` | Apache-2.0 | Complete cross-platform desktop and mobile email client with multi-account IMAP/SMTP, SQLite database, and "Ledger Desk" UI. |
| **Spam Core Engine** | `packages/spam_core/` | Apache-2.0 | Standalone pure-Dart classification library containing Robinson-Fisher Bayes, MinHash LSH, URL hashing, and auth parser. |
| **Prior Trainer** | `tools/train_prior/` | Apache-2.0 | Offline CLI utility to process raw corpora and export bundled Bayesian seed priors (`prior_model.json`). |
| **Protocol Specifications** | `docs/reference/backend-protocol.md` | Apache-2.0 | Documented HTTP specifications for anonymous community report submission, blocklist distribution, and sync endpoints. |
| **Community Backend** | Proprietary Hosted Service | Closed Source | Multi-tenant FastAPI service implementing $K \ge 3$ distinct-source thresholding, daily salt rotation, and abuse mitigation. |
| **Filter Sync Storage** | Proprietary Hosted Service | Closed Source | Hosted blob storage for syncing end-to-end encrypted (AES-256-GCM) filter state across user devices. |
| **Pro Entitlement Service** | Proprietary Hosted Service | Closed Source | Receipt verification and subscription management service for DataFortress Pro accounts. |

---

## Free vs. Pro Feature Matrix

All core email functionality, local intelligence, and collective defense features are entirely free and open source:

| Feature | Free Tier | Pro Tier | Notes |
| --- | :---: | :---: | --- |
| **Local Bayesian Spam Filter** | Yes | Yes | Runs entirely on-device; learns continuously from user verdicts. |
| **Three-Class Sorting** | Yes | Yes | Categorizes into Inbox, Newsletter, and Spam with tactile stamps and 8-second undo. |
| **Signal Ledger (Evidence Sheet)** | Yes | Yes | Inspect exact Bayesian token weights, SPF/DKIM/DMARC status, and heuristics. |
| **Anonymous Community Blocklist** | Yes | Yes | Consumes public community blocklists and submits zero-ID cryptographic hashes. |
| **HTML Sanitizer & Image Shield** | Yes | Yes | Blocks remote tracking pixels and strips dangerous HTML elements. |
| **Google / Microsoft Sign-In** | Yes | Yes | OAuth2 with PKCE straight to the provider, tokens kept in the platform secure store; needs OAuth client IDs compiled into the build. |
| **New-Mail Notifications** | Yes | Yes | Local notifications (sender and subject only): every message, bundled every 5 minutes, or hourly. |
| **Multi-Device E2EE Filter Sync** | No | Yes | Synchronizes trained Bayes token counts across devices using AES-256-GCM and CRDT PN-counters. |
| **On-Device ONNX Neural Scorer** | No | Yes | Secondary on-device transformer model for ambiguous message scoring. |

---

## Policy on Self-Hosting

**Self-hosting the backend is not supported; the protocol is documented.**

The hosted community backend and synchronization infrastructure are proprietary services operated by DataFortress. No server source code, Docker containers, Kubernetes manifests, or deployment scripts are provided in this repository.

Developers wishing to operate an independent backend may implement an alternate server conforming to the HTTP specifications documented in [Backend Protocol](reference/backend-protocol.md). The client API endpoint can be redirected at compile time using the `BACKEND_URL` environment variable:

```bash
flutter run -d linux --dart-define=BACKEND_URL=https://custom-backend.example.com
```

---

## Third-Party Licenses & Bundled Fonts

### Font Licenses

All bundled typefaces located under `app/assets/fonts/` are distributed under the **SIL Open Font License 1.1 (OFL 1.1)**:

- **Fraunces**: Designed by Phaedra Charles and Flavia Zimbardi (SIL OFL 1.1).
- **Public Sans**: Developed by the United States Web Design System / GSA (SIL OFL 1.1).
- **JetBrains Mono**: Created by JetBrains (SIL OFL 1.1).

### Key Software Dependencies

- **`enough_mail`**: Mozilla Public License 2.0 (MPL-2.0). Provides IMAP, SMTP, and MIME parsing capabilities.
- **`sqlite3`**: MIT License / BSD-3-Clause. Embedded relational persistence.
- **`dio`**: MIT License. HTTP client for community blocklists and API interaction.
- **`flutter_riverpod`**: MIT License. Reactive state management.
- **`pointycastle` / `crypto`**: MIT License / BSD-3-Clause. Cryptographic primitives for hashing and encryption.

---

## Trademarks and Brand Assets

The code and documentation in this repository are licensed under the Apache License 2.0. However, the Apache-2.0 license **does not grant any trademark rights**.

- The **DataFortress** name, trade name, and logotypes are proprietary trademarks of Justin Guese.
- The visual brand assets, including `logo.png` and icons located in `app/assets/icon/`, are reserved and may not be used in derivative works without explicit written authorization.
- Forks and redistributions of this codebase must remove the DataFortress name and brand artwork, replacing them with independent project branding.
