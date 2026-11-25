# Anonymous Community Spam Fingerprint Sharing & Privacy Architecture

!!! warning "Legal Notice"
    This document includes a draft legal basis analysis that **needs legal review** prior to commercial production deployment under EU GDPR / UK GDPR / ePrivacy Directive.

## 1. Overview & Core Privacy Guarantee

DataFortress Mail provides an on-device learning spam filter complemented by an anonymous community sharing network. The community channel operates under strict zero-knowledge principles:
- **No Identifiers:** `POST /v1/reports` and `POST /v1/votes/ham` carry no user ID, device ID, installation ID, or session cookie.
- **No Content Transmission:** Email bodies, subject lines, senders, and recipient addresses never leave the client device.
- **No IP Persistence:** Client IP addresses are never written to database tables and are excluded from public endpoint request logging.
- **No Tracking:** Source counting is conducted solely via a rotating ephemeral `HMAC(daily_salt, subnet_prefix)` where the daily salt is rotated and permanently deleted every 24 hours.

---

## 2. Exact Payload Specification

### `POST /v1/reports`
Submits anonymous cryptographic fingerprints for an email marked as spam:

```json
{
  "body_bands": [1839281928371928, 9283719283719283, ...],
  "url_hashes": [4829103948102938, 7192830192837461],
  "sender_domain_hash": 5829102938471029,
  "pow": "report_1700000000000:4821",
  "app_check": "ey..."
}
```

#### Field Details:
1. `body_bands` (`List<u64>`, optional):
   - 8 x 64-bit integers computed using MinHash (32 permutations) partitioned into 8 LSH bands of 4 hashes each.
   - **Guard:** Omitted entirely for messages with fewer than 40 words to prevent fingerprinting short personal correspondence.
2. `url_hashes` (`List<u64>`):
   - 64-bit integer hashes computed from extracted URLs.
   - URLs are normalized to `eTLD+1` and `host + first path segment`. All query parameters, fragments, userinfo, and session tokens are strictly stripped before hashing.
3. `sender_domain_hash` (`u64`, optional):
   - 64-bit hash of the sender's domain.
   - **Freemail Guard:** Skipped entirely for freemail providers (e.g., `gmail.com`, `yahoo.com`, `outlook.com`, `icloud.com`, `proton.me`, etc.) and top Tranco domains to prevent false positives against shared domains.
4. `pow` (`string`, optional):
   - Proof-of-work challenge-response (`challenge:nonce`) satisfying leading zero-bit difficulty. Thwarts automated report flooding without identifying the client.
5. `app_check` (`string`, optional):
   - Device/platform attestation token (Firebase App Check) verifying genuine app binary execution.

### `POST /v1/votes/ham`
Submits a dispute when a user rescues a falsely classified email from Junk to Inbox:

```json
{
  "fingerprint_ids": [4829103948102938, 7192830192837461]
}
```

**Guard:** Ham votes are rejected for fingerprints that are not currently active on the community blocklist.

---

## 3. Activation, Decay & Retention Policy

1. **Activation Threshold (K-Threshold):**
   - A candidate fingerprint is **Pending** until it has been reported by **$K \ge 3$ distinct sources** within a rolling 7-day window, AND total spam reports exceed **$2 \times \text{ham votes}$**.
   - URLhaus feeds and high-confidence threat feeds activate at $K=1$.
   - Popular domains (Tranco top 1,000) and freemail domains **never** activate.
2. **Decay & Expiration:**
   - Pending fingerprints are purged after **14 days** if the activation threshold is not met.
   - Active fingerprints expire automatically **90 days** after the last confirmed spam report.
3. **Daily Salt Rotation:**
   - Ephemeral per-day source counting uses `HMAC(daily_salt, subnet)`.
   - The `daily_salt` is rotated and destroyed every 24 hours, making past source identifiers cryptographically irreversible.

---

## 4. Legal Basis Draft (*Needs Legal Review*)

- **GDPR Article 6(1)(f) — Legitimate Interests:**
  Processing of technical threat telemetry and cryptographic hashes is pursued for the legitimate interest of ensuring network and information security (Recital 49 GDPR). The processing constitutes minimal, privacy-preserving technical indicators without personal identifying data.
- **ePrivacy Directive Article 5(3):**
  Exempt under the strictly necessary criterion for delivering requested cybersecurity and email filtering protection.
- **User Choice:**
  Community sharing is enabled by default with clear inline disclosure upon first spam classification and can be toggled off at any time in Settings.

---

## 5. Unsubscribe Protocol & Safety Specification

DataFortress Mail implements RFC 8058 One-Click unsubscribe and RFC 2369 mailto unsubscribe directly from the client device. This protocol functions entirely outside the backend infrastructure:

### Network Isolation
- **Direct Endpoints Only:** HTTPS POST requests connect directly to the host specified in `List-Unsubscribe`. Mailto requests are sent via the user's existing authenticated SMTP server.
- **Zero Backend Ingestion:** The DataFortress backend never receives, proxies, logs, or coordinates unsubscribe requests.
- **No Third-Party Trackers:** Plain HTTP GET links (URLs lacking RFC 8058 `List-Unsubscribe-Post: List-Unsubscribe=One-Click`) are intentionally never automated or fetched, preventing tracking or liveness confirmation.

### Exact Payload & Request Specification

#### RFC 8058 One-Click HTTPS POST
- **Method:** `POST`
- **Target URL:** Published `List-Unsubscribe` HTTPS URI (standard port 443 only).
- **Headers:**
  - `Content-Type: application/x-www-form-urlencoded`
  - `User-Agent: DataFortress-Mail/1.0`
  - Zero cookies, zero platform tokens, zero authorization headers, zero installation or hardware IDs.
- **Body:** `List-Unsubscribe=One-Click`
- **Redirects:** `followRedirects: false` (3xx redirects are treated as `failed` and not pursued).
- **Timeout:** 10 seconds.

#### RFC 2369 Mailto
- **Envelope:** Sent through user's active IMAP/SMTP account credentials.
- **Recipient:** Exactly one destination email parsed from `mailto:`.
- **Subject / Body:** Parsed from URI parameters if present (capped at 200 characters) or default `unsubscribe`.
- **Header Injection Guard:** Any newline (`\r` or `\n`) or header parameters (`cc`, `bcc`) invalidate the target.
- **Sent Folder:** Message is sent via SMTP but not appended to the IMAP Sent folder.

### Safety Guards Matrix

| Guard | Condition & Action |
|---|---|
| **Undo Window** | Verdict trigger executes after a 10-second delay. Any user `undo()` or non-spam verdict cancels the pending action. Undoing a ham verdict to restore spam does not schedule an unsubscribe. |
| **SSRF & URL Validation** | Enforced by `DfSafeUrlGuard` (`package:df_safe_url`). HTTPS only, port 443 only, no userinfo, host not localhost/`.local`/`.internal`. Hostname is pre-resolved via DNS: all resolved IPv4 and IPv6 addresses must be public (blocks `127.0.0.0/8`, `::1`, `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`, `169.254.0.0/16`, `fe80::/10`, `100.64.0.0/10` CGNAT, `fc00::/7` ULA). |
| **Sender Authentication** | Verdict-based trigger requires verified authentication (`dmarc=pass` or `dkim=pass` in `Authentication-Results`). Unauthenticated emails skip automated unsubscribe (`skippedUnauthenticated`). Manual user click in reader bypasses this requirement. |
| **Rate Capping** | Maximum of 20 unsubscribe attempts across all accounts per rolling 24-hour window (`skippedRateLimited`). |
| **Idempotency** | Tracked in local SQLite table `unsubscribe_log`. Successful attempts deduplicated for 30 days per `(account_id, sender_domain)` (`skippedDuplicate`). Failures back off for 24 hours, with a hard cap of 3 attempts. |
| **Self-Domain Guard** | Skipped if the sender domain matches the receiving account domain (`skippedSelfDomain`). |
| **Settings Off Switch** | Key `auto_unsubscribe` in `settings` table (defaults to `true`). When toggled off, verdict triggers are skipped (`skippedDisabled`). |
