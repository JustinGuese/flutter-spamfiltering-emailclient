# Backend Protocol Reference

> The hosted backend is proprietary; this is the contract the client implements.

This document describes the exact HTTP REST API and cryptographic payload shapes expected by the client code (`app/lib/community/report_client.dart`, `app/lib/community/blocklist_sync.dart`, `app/lib/premium/filter_sync.dart`, and `app/lib/api/api_client.dart`).

All endpoints are relative to `BACKEND_URL` (default `http://localhost:8000`).

---

## 1. Anonymous Community Threat Telemetry

The community client communicates anonymously. Calls never transmit account IDs, Firebase UID, device IDs, installation UUIDs, or cookies.

### `POST /v1/reports`

Submits anonymous cryptographic spam fingerprints when a user marks an email as spam or when high-confidence spam is processed.

- **Client Implementation**: `app/lib/community/report_client.dart`
- **Authentication**: None (Anonymous)
- **Headers**:
  - `Accept: application/json`
  - `Content-Type: application/json`

#### Request Payload

```json
{
  "body_bands": [1839281928371928, 9283719283719283],
  "url_hashes": [4829103948102938, 7192830192837461],
  "sender_domain_hash": 5829102938471029,
  "pow": "report_1700000000000:4821",
  "app_check": "ey..."
}
```

| Field | Type | Description |
|---|---|---|
| `body_bands` | `List<int>` | 8x 64-bit positive integers from MinHash LSH bands. Omitted if body has < 40 words. |
| `url_hashes` | `List<int>` | 64-bit integer hashes of normalized `eTLD+1` and `host + first path segment`. |
| `sender_domain_hash` | `int?` | 64-bit hash of sender domain. Omitted for freemail domains. |
| `pow` | `string` | Hashcash string `challenge:nonce` satisfying 8 leading zero bits over `sha256(challenge:nonce)`. Generated from challenge `report_<timestamp_ms>`. |
| `app_check` | `string?` | Platform attestation token (Firebase App Check), if configured. |

#### Responses & Error Handling
- `200 OK` or `201 Created`: Report accepted.
- Client logs error via `logError('community report', ...)` and returns `false` on network or HTTP error status codes.

---

### `POST /v1/votes/ham`

Submits a dispute when a user moves a falsely classified message from Junk/Spam to Inbox.

- **Client Implementation**: `app/lib/community/report_client.dart`
- **Authentication**: None (Anonymous)
- **Headers**: `Accept: application/json`, `Content-Type: application/json`

#### Request Payload

```json
{
  "hashes": [4829103948102938, 7192830192837461]
}
```

| Field | Type | Description |
|---|---|---|
| `hashes` | `List<int>` | Fingerprint hash values to vote ham against. |

#### Responses & Error Handling
- `200 OK` or `204 No Content`: Vote accepted.
- Client catches exceptions, logs via `logError('community vote ham', ...)`, and returns `false`.

---

## 2. Community Blocklist Distribution

Clients periodically synchronize the community blocklist to perform zero-latency on-device lookups.

### `GET /v1/blocklist/snapshot`

Downloads the complete active blocklist dataset. Invoked on first launch or when the local blocklist version is `0`.

- **Client Implementation**: `app/lib/community/report_client.dart`, `app/lib/community/blocklist_sync.dart`
- **Authentication**: None (Anonymous)
- **Query Parameters**: None

#### Response Payload

```json
{
  "version": 42,
  "fingerprints": [
    {
      "id": "fp_1001",
      "type": "url_hash",
      "hash": 4829103948102938
    },
    7192830192837461
  ]
}
```

Entries can be structured objects (`{"id": string, "type": string, "hash": int}`) or raw integer hash values.

#### Database Persistence
Stored in the local Drift SQLite table `blocklist_entries`. Version is saved to `settings` under key `blocklist_version`.

---

### `GET /v1/blocklist/delta`

Fetches incremental additions and revocations since a known version.

- **Client Implementation**: `app/lib/community/report_client.dart`, `app/lib/community/blocklist_sync.dart`
- **Authentication**: None (Anonymous)
- **Query Parameters**:
  - `since` (integer): Local `blocklist_version`

#### Response Payload

```json
{
  "version": 43,
  "added": [
    {
      "id": "fp_1002",
      "type": "body_band",
      "hash": 9283719283719283
    }
  ],
  "removed": [
    { "id": "fp_1001" },
    7192830192837461
  ]
}
```

#### Client Processing
Executed inside an atomic transaction: deletes IDs/hashes in `removed`, inserts entries in `added`, and updates `blocklist_version`.

---

## 3. Premium Filter Sync (E2EE)

Filter synchronization for Pro users synchronizes token counters across devices using client-side AES-256-GCM encryption and CRDT PN-counters.

- **Client Implementation**: `app/lib/premium/filter_sync.dart`, `app/lib/api/api_client.dart`
- **Authentication**: `Authorization: Bearer <Firebase_ID_Token>` injected by `authenticatedDioProvider`.

### `PUT /v1/sync/blobs/{slot}`

Uploads an encrypted blob containing the current device's CRDT token counter state.

- **Path Parameters**: `slot` (string, e.g. `slot_0`)
- **Request Payload**:
  ```json
  {
    "ciphertext": "<base64 encoded 12-byte IV + AES-256-GCM ciphertext + 16-byte auth tag>"
  }
  ```
- **Responses**: `200 OK` or `204 No Content`.

### `GET /v1/sync/blobs`

Fetches all synced blobs for the authenticated account across all paired devices.

- **Response Payload**:
  ```json
  [
    {
      "slot": "slot_1",
      "ciphertext": "<base64 string>"
    }
  ]
  ```
- **Client Processing**: Decrypts each non-local slot using the client-side master sync key, deserializes `CrdtTokenState`, and applies token counts to `tokenStore`.

### `GET /v1/sync/blobs/{slot}`

Fetches a specific device slot blob.

- **Response Payload**:
  ```json
  {
    "ciphertext": "<base64 string>"
  }
  ```

---

## 4. Advanced Model Download (Pro)

### `GET /v1/models/advanced`
Requires an entitled, authenticated user. Returns a JSON object whose `download_url` field the client then fetches directly (`dio.download`) and stores as `advanced_spam_model.onnx` in the app documents directory (`app/lib/premium/model_downloader.dart`). Any non-200 response or error leaves the app without the model; the Bayes filter keeps working.

```json
{ "download_url": "https://..." }
```

---

## Error Handling Summary

| Scenario | HTTP Status | Client Behavior |
|---|---|---|
| Invalid PoW or payload | `400 Bad Request` | Fails gracefully; logs error. |
| Missing/expired auth on `/sync` | `401 Unauthorized` | Interceptor attempts token refresh or prompts user login. |
| Feature not entitled | `403 Forbidden` | Sync disabled; client keeps local-only token store. |
| Rate limited | `429 Too Many Requests` | Sync postponed to next scheduled cycle (6h for blocklist). |
| Server unavailable | `5xx` / timeout | Client continues in offline mode; local Bayes scoring unaffected. |

See also:
- [Community Privacy Spec](../concepts/privacy-spec.md)
- [Spam Core API](spam-core-api.md)
- [Database Schema](database.md)
