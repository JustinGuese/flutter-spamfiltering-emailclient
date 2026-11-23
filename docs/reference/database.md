# Database Schema Reference

The client stores everything locally in SQLite through the `sqlite3` package, using hand-written SQL. The schema that actually runs is the `CREATE TABLE IF NOT EXISTS` block in `AppDatabase._createTables()` (`app/lib/db/database.dart`).

!!! note
    `app/lib/db/tables.dart` is a Drift-style declaration of the same schema. It is **not wired in** (no code generation, nothing imports it), and it does not list the `pending_imap_actions` table. The column listings below come from it, so if the two ever disagree, `database.dart` is the source of truth.

All tables are created and managed on-device. No personal email data or credentials ever reside on external servers.

---

## Tables

### 1. `Accounts` (`accounts`)
Stores configured IMAP/SMTP mail accounts.

| Column | Declared type | Constraints | Description |
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

| Column | Declared type | Constraints | Description |
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

| Column | Declared type | Constraints | Description |
|---|---|---|---|
| `id` | `TextColumn` | `primaryKey` | Internal message UUID. |
| `accountId` | `TextColumn` | | Owning account UUID. |
| `folderId` | `TextColumn` | | Owning folder UUID. |
| `uid` | `IntColumn` | | IMAP UID within the folder. |
| `messageId` | `TextColumn` | `nullable` | Standard RFC 2822 `Message-ID` header. |
| `subject` | `TextColumn` | | Message subject line. |
| `sender` | `TextColumn` | | Full `From` header string (`Name <user@domain>`). |
| `senderDomain` | `TextColumn` | `nullable` | Extracted sender domain. |
| `recipientAddrs`| `TextColumn` | | Comma-separated `To` addresses (bare emails). `Cc` is kept separately in `ccAddrs`. |
| `ccAddrs` | `TextColumn` | `default: ''` | Comma-separated `Cc` addresses, used by Reply All. Added by `AppDatabase._migrate()`; mail synced before it existed keeps `''` until re-fetched. It is in `database.dart` only, not in `tables.dart`. |
| `date` | `DateTimeColumn` | | Message origination timestamp. |
| `snippet` | `TextColumn` | | Cleaned text preview snippet. |
| `isRead` | `BoolColumn` | `default: false` | Message read flag (`\Seen`). |
| `isFlagged` | `BoolColumn` | `default: false` | Message starred/flagged (`\Flagged`). |
| `hasAttachments`| `BoolColumn` | `default: false` | True when the message has at least one row in `attachments` (set from the same list when the message is stored). |
| `classificationLabel` | `TextColumn` | `default: 'inbox'` | Current label: `inbox`, `spam`, `newsletter`. |
| `spamScore` | `RealColumn` | `default: 0.0` | Computed spam probability score (0.0 to 1.0). |

---

### 4. `Bodies` (`bodies`)
Message body content separated from headers for storage and query efficiency.

| Column | Declared type | Constraints | Description |
|---|---|---|---|
| `messageId` | `TextColumn` | `primaryKey` | Foreign key reference to `messages.id`. |
| `textBody` | `TextColumn` | `nullable` | Plaintext email body. |
| `htmlBody` | `TextColumn` | `nullable` | Raw HTML email body. |
| `sanitizedHtml` | `TextColumn` | `nullable` | Sanitized HTML safe for display. |
| `remoteImagesBlocked` | `BoolColumn` | `default: true` | Whether external remote tracking images are blocked. |

---

### 5. `Contacts` (`contacts`)
Known contacts and sender trust rules.

| Column | Declared type | Constraints | Description |
|---|---|---|---|
| `id` | `TextColumn` | `primaryKey` | Unique contact UUID. |
| `email` | `TextColumn` | | Contact email address. |
| `name` | `TextColumn` | `nullable` | Contact display name. |
| `trustLevel` | `IntColumn` | `default: 0` | Sender reputation (-1 untrusted, 0 neutral, 1 trusted). |
| `alwaysAllowImages` | `BoolColumn` | `default: false` | Bypass remote image blocking for this contact. |

---

### 6. `Classifications` (`classifications`)
Detailed explainable scoring audit log for each classified message.

| Column | Declared type | Constraints | Description |
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

| Column | Declared type | Constraints | Description |
|---|---|---|---|
| `hash` | `Int64Column` | `primaryKey` | Positive 63-bit SHA-256 token hash. |
| `spam` | `IntColumn` | `default: 0` | Spam training count. |
| `ham` | `IntColumn` | `default: 0` | Ham training count. |
| `newsletter` | `IntColumn` | `default: 0` | Newsletter training count. |
| `inbox` | `IntColumn` | `default: 0` | Inbox transactional/personal training count. |

---

### 8. `BlocklistEntries` (`blocklist_entries`)
Active community spam indicators synchronized from the backend.

| Column | Declared type | Constraints | Description |
|---|---|---|---|
| `id` | `TextColumn` | `primaryKey` | Indicator ID (e.g. `fp_123456`). |
| `type` | `TextColumn` | | Indicator type: `body_band`, `url_hash`, `sender_domain`. |
| `hashValue` | `Int64Column` | | 63-bit positive hash value to match. |
| `addedAt` | `DateTimeColumn` | | Sync timestamp. |
| `expiresAt` | `DateTimeColumn` | `nullable` | Optional expiration timestamp. |

---

### 9. `Settings` (`settings`)
Key-value preferences and synchronization metadata.

| Column | Declared type | Constraints | Description |
|---|---|---|---|
| `key` | `TextColumn` | `primaryKey` | Setting identifier (e.g. `blocklist_version`, `blocklist_last_sync`). |
| `value` | `TextColumn` | | Value string. |

---

### 10. `pending_imap_actions`
Queue of IMAP changes (for example a message moved after a verdict) that still have to be applied on the server. Defined only in `database.dart`.

| Column | Type | Description |
|---|---|---|
| `id` | `INTEGER` | Auto-increment primary key. |
| `account_id` | `TEXT` | Owning account. |
| `message_id` | `TEXT` | Local message ID. |
| `uid` | `INTEGER` | IMAP UID of the message. |
| `folder_id` | `TEXT` | Folder the message is in. |
| `action` | `TEXT` | Action to apply on the server. |
| `target_folder` | `TEXT` | Destination folder, if the action moves the message. Nullable. |

### 11. `attachments`
The files of a received message: names and IMAP part numbers only. The bytes stay on the mail server until the user opens or saves the file (see [Attachments](../concepts/architecture.md#attachments)). Defined only in `database.dart` (`CREATE TABLE IF NOT EXISTS`, so existing databases gain it on the next start).

| Column | Type | Description |
|---|---|---|
| `id` | `INTEGER` | Auto-increment primary key. Kept stable across re-syncs of an unchanged message, because a forward draft refers to it. |
| `message_id` | `TEXT` | Local message ID (`messages.id`). Indexed. |
| `fetch_id` | `TEXT` | IMAP part number inside the message (`2`, `1.2`), the numbering `MimeMessage.getPart` resolves. |
| `filename` | `TEXT` | File name reduced to a safe base name (no directories, control or reserved characters). |
| `mime_type` | `TEXT` | Media type of the part. |
| `size` | `INTEGER` | Bytes. An estimate from the encoded size until the file is downloaded, then the real size. `0` when unknown. |

Rows are deleted with their account and rewritten when a message is stored again with a different file list. Mail stored before this table existed has no rows; they are filled in from the server the first time the message is opened.

### 12. `search_index` (FTS5 virtual table)
Full-text index behind the Search tab. Not declared in `tables.dart`; it is created in `AppDatabase._createSearchIndex()` (`app/lib/db/database.dart`).

| Column | Description |
|---|---|
| `subject`, `sender`, `recipients`, `body` | Indexed text, taken from `messages` (recipients = To + Cc) and `bodies.text_body`. Tokenizer: `unicode61 remove_diacritics 2`. |
| `rowid` | The `rowid` of the matching `bodies` row, which is how a hit is joined back to its message. |

Three triggers on `bodies` (insert, update, delete) keep it current, so no sync path has to know about it. `AppDatabase` sets `PRAGMA recursive_triggers = ON` so that `INSERT OR REPLACE` (what the sync engine uses) fires the delete trigger. If the table does not exist yet, it is created and filled from the mail already stored. The index holds a copy of the message text and never leaves the device.

---

## Schema Management

- Database operations go through `AppDatabase` (`app/lib/db/database.dart`); the UI and services run SQL on `db.db` directly.
- Tables are created with `CREATE TABLE IF NOT EXISTS` on every start. There is no schema version. `AppDatabase._migrate()` runs after table creation and adds missing columns one at a time (it checks `PRAGMA table_info` first, so it is safe on fresh and existing databases); currently it adds `messages.cc_addrs`. Any further change to an existing table needs a step there. `_createSearchIndex()` runs last and is idempotent.
- Bayesian counts implement the `TokenStore` interface via `TokenStoreDrift` (`app/lib/filter/token_store_drift.dart`).
- Password credentials are **never** stored in the SQLite database; they are stored in the OS platform keychain/secret storage (`libsecret` on Linux, Keychain on macOS/iOS, DPAPI/Credential Manager on Windows, EncryptedSharedPreferences on Android).

See also:
- [Spam Core API](spam-core-api.md)
- [Backend Protocol](backend-protocol.md)
- [Project Layout](project-layout.md)
