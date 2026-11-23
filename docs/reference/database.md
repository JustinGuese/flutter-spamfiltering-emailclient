# Database Schema Reference

The client uses [Drift](https://drift.simonbinder.eu/) (SQLite) for all local persistence. The schema is defined in `app/lib/db/tables.dart`.

All tables are created and managed on-device. No personal email data or credentials ever reside on external servers.

---

## Tables

### 1. `Accounts` (`accounts`)
Stores configured IMAP/SMTP mail accounts.

| Column | Drift Type | Constraints | Description |
|---|---|---|---|
| `id` | `TextColumn` | `primaryKey` | Unique account UUID. |
| `email` | `TextColumn` | | User email address. |
| `displayName` | `TextColumn` | | User display name. |
| `imapHost` | `TextColumn` | | IMAP server hostname. |
| `imapPort` | `IntColumn` | | IMAP port (e.g. 993). |
| `smtpHost` | `TextColumn` | | SMTP server hostname. |
| `smtpPort` | `IntColumn` | | SMTP port (e.g. 465 or 587). |
| `authType` | `TextColumn` | `default: 'password'` | Authentication type (`password` or `oauth2`). |
| `createdAt` | `DateTimeColumn` | | Account creation timestamp. |

---

### 2. `Folders` (`folders`)
Mailbox folders associated with an account.

| Column | Drift Type | Constraints | Description |
|---|---|---|---|
| `id` | `TextColumn` | `primaryKey` | Unique folder UUID. |
| `accountId` | `TextColumn` | | Foreign key reference to `accounts.id`. |
| `name` | `TextColumn` | | Localized/display name. |
| `serverPath` | `TextColumn` | | IMAP mailbox path (e.g. `INBOX`, `[Gmail]/Spam`). |
| `specialUse` | `TextColumn` | `nullable` | RFC 6154 role: `inbox`, `sent`, `drafts`, `trash`, `junk`, `archive`. |
| `uidValidity` | `IntColumn` | `nullable` | IMAP `UIDVALIDITY` value. |
| `lastSeenUid` | `IntColumn` | `nullable` | Highest synchronized IMAP UID. |
| `unreadCount` | `IntColumn` | `default: 0` | Cached unread count. |

---

### 3. `Messages` (`messages`)
Synchronized email message envelopes and classification metadata.

| Column | Drift Type | Constraints | Description |
|---|---|---|---|
| `id` | `TextColumn` | `primaryKey` | Internal message UUID. |
| `accountId` | `TextColumn` | | Owning account UUID. |
| `folderId` | `TextColumn` | | Owning folder UUID. |
| `uid` | `IntColumn` | | IMAP UID within the folder. |
| `messageId` | `TextColumn` | `nullable` | Standard RFC 2822 `Message-ID` header. |
| `subject` | `TextColumn` | | Message subject line. |
| `sender` | `TextColumn` | | Full `From` header string (`Name <user@domain>`). |
| `senderDomain` | `TextColumn` | `nullable` | Extracted sender domain. |
| `recipientAddrs`| `TextColumn` | | Comma-separated recipient email addresses. |
| `date` | `DateTimeColumn` | | Message origination timestamp. |
| `snippet` | `TextColumn` | | Cleaned text preview snippet. |
| `isRead` | `BoolColumn` | `default: false` | Message read flag (`\Seen`). |
| `isFlagged` | `BoolColumn` | `default: false` | Message starred/flagged (`\Flagged`). |
| `hasAttachments`| `BoolColumn` | `default: false` | Attachment presence flag. |
| `classificationLabel` | `TextColumn` | `default: 'inbox'` | Current label: `inbox`, `spam`, `newsletter`. |
| `spamScore` | `RealColumn` | `default: 0.0` | Computed spam probability score (0.0 to 1.0). |

---

### 4. `Bodies` (`bodies`)
Message body content separated from headers for storage and query efficiency.

| Column | Drift Type | Constraints | Description |
|---|---|---|---|
| `messageId` | `TextColumn` | `primaryKey` | Foreign key reference to `messages.id`. |
| `textBody` | `TextColumn` | `nullable` | Plaintext email body. |
| `htmlBody` | `TextColumn` | `nullable` | Raw HTML email body. |
| `sanitizedHtml` | `TextColumn` | `nullable` | Sanitized HTML safe for display. |
| `remoteImagesBlocked` | `BoolColumn` | `default: true` | Whether external remote tracking images are blocked. |

---

### 5. `Contacts` (`contacts`)
Known contacts and sender trust rules.

| Column | Drift Type | Constraints | Description |
|---|---|---|---|
| `id` | `TextColumn` | `primaryKey` | Unique contact UUID. |
| `email` | `TextColumn` | | Contact email address. |
| `name` | `TextColumn` | `nullable` | Contact display name. |
| `trustLevel` | `IntColumn` | `default: 0` | Sender reputation (-1 untrusted, 0 neutral, 1 trusted). |
| `alwaysAllowImages` | `BoolColumn` | `default: false` | Bypass remote image blocking for this contact. |

---

### 6. `Classifications` (`classifications`)
Detailed explainable scoring audit log for each classified message.

| Column | Drift Type | Constraints | Description |
|---|---|---|---|
| `messageId` | `TextColumn` | `primaryKey` | Foreign key reference to `messages.id`. |
| `label` | `TextColumn` | | Predicted label (`spam`, `ham`, `newsletter`, `inbox`). |
| `spamScore` | `RealColumn` | | Overall combined spam score. |
| `evidenceJson` | `TextColumn` | | Serialized list of `Evidence` objects displayed in the Evidence Sheet. |
| `classifiedAt` | `DateTimeColumn` | | Timestamp of classification execution. |
| `userOverridden`| `BoolColumn` | `default: false` | `true` if manually changed by user (e.g. marked spam / not spam). |

---

### 7. `Tokens` (`tokens`)
On-device Bayesian token dictionary storing occurrences across categories.

| Column | Drift Type | Constraints | Description |
|---|---|---|---|
| `hash` | `Int64Column` | `primaryKey` | Positive 63-bit SHA-256 token hash. |
| `spam` | `IntColumn` | `default: 0` | Spam training count. |
| `ham` | `IntColumn` | `default: 0` | Ham training count. |
| `newsletter` | `IntColumn` | `default: 0` | Newsletter training count. |
| `inbox` | `IntColumn` | `default: 0` | Inbox transactional/personal training count. |

---

### 8. `BlocklistEntries` (`blocklist_entries`)
Active community spam indicators synchronized from the backend.

| Column | Drift Type | Constraints | Description |
|---|---|---|---|
| `id` | `TextColumn` | `primaryKey` | Indicator ID (e.g. `fp_123456`). |
| `type` | `TextColumn` | | Indicator type: `body_band`, `url_hash`, `sender_domain`. |
| `hashValue` | `Int64Column` | | 63-bit positive hash value to match. |
| `addedAt` | `DateTimeColumn` | | Sync timestamp. |
| `expiresAt` | `DateTimeColumn` | `nullable` | Optional expiration timestamp. |

---

### 9. `Settings` (`settings`)
Key-value preferences and synchronization metadata.

| Column | Drift Type | Constraints | Description |
|---|---|---|---|
| `key` | `TextColumn` | `primaryKey` | Setting identifier (e.g. `blocklist_version`, `blocklist_last_sync`). |
| `value` | `TextColumn` | | Value string. |

---

## Schema Evolution & DAOs

- Database operations are accessed through `AppDatabase` (`app/lib/db/database.dart`).
- Bayesian counts implement the `TokenStore` interface via `TokenStoreDrift` (`app/lib/filter/token_store_drift.dart`).
- Password credentials are **never** stored in the SQLite database; they are stored in the OS platform keychain/secret storage (`libsecret` on Linux, Keychain on macOS/iOS, DPAPI/Credential Manager on Windows, EncryptedSharedPreferences on Android).

See also:
- [Spam Core API](spam-core-api.md)
- [Backend Protocol](backend-protocol.md)
- [Project Layout](project-layout.md)
