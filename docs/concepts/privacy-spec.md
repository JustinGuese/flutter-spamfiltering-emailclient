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
