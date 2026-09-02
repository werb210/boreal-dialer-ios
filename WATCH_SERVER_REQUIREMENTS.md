# Independent Watch server requirements

No BF-Server code is changed by this repository. “Required” below means the Watch boundary is present but deliberately returns `serverCapabilityUnavailable` where no verified contract exists.

## Already exists (verified in the iPhone client)

- Production HTTPS base API: `https://server.boreal.financial/api`.
- Staff OTP operations: `POST /api/auth/otp/start` and `POST /api/auth/otp/verify`.
- Twilio iPhone token: `POST /api/voice/token`; this is **not** a watchOS media capability.
- BI-only CRM reads exist, including `GET /api/v1/bi/crm/contacts?pageSize=…`; this is not yet treated as a cross-silo Watch search contract.
- CRM call-event logging exists at `POST /api/communications/call-events`, owned by the established phone/server calling flow.

## Required and not claimed to exist

1. **Watch authentication/device linking:** issue an independently refreshable, revocable `watchos` device session. Permit safe one-time enrollment from an authenticated iPhone and a standalone OTP/device-code path. Define refresh, expiry, rate limits, and lost-device revocation.
2. **Device registration:** authenticated upsert/delete contract for `{deviceId, platform, app, pushType, token}`. Store iPhone standard APNs, iPhone VoIP, and Watch standard APNs as three registrations. Never accept tokens for another owned device implicitly.
3. **Direct APNs:** send eligible ordinary events to both iPhone and Watch registrations. Supported Boreal types include client/staff message, task, meeting, missed call, voicemail, stage/application update, and safe call information. Use categories `MESSAGE`, `TASK`, `MEETING`, and `MISSED_CALL`. Minimize lock-screen data.
4. **Contact search:** authorized, silo-aware, paginated search returning a maximum small set of `{id,name,company,primaryPhone}`. Do not expose a full CRM export.
5. **Recents:** bounded, server-authoritative records containing name/number, incoming/outgoing/missed direction, timestamp, and Boreal line.
6. **Standalone call bridge/status/cancellation and incoming routing:** exactly as specified in [WATCH_CALL_SERVER_CONTRACT.md](WATCH_CALL_SERVER_CONTRACT.md), including trusted callback configuration.
7. **Presence:** low-frequency lifecycle updates (`available`, `offline`, `standaloneCellular`, `companionAvailable`, `busy`) with server-side expiry; APNs and on-demand requests should replace idle polling.
8. **Session/device revocation:** logout one Watch independently, remove its push registration, clear routing, and allow account-wide revocation so iPhone logout/security action cannot leave a forgotten Watch session indefinitely.

Server capability discovery or configuration must expose only confirmed endpoints. Until then, the production Watch client does not guess URLs, upload its token, claim contact/recents availability, or claim a bridge call started.

## Proposed HTTP contract for server implementation

These routes are requirements for a future Boreal server change; **none is
claimed to exist and none is called by this PR**. All requests use HTTPS,
`Authorization: Bearer <watch-device-session>`, JSON, and an opaque server
device ID. Mutations also require `Idempotency-Key`.

| Capability | Proposed operation | Request | Successful response |
| --- | --- | --- | --- |
| Authentication | `POST /api/watch/auth/link` | `{ "oneTimeCode": "…", "device": { "platform": "watchos", "name": "…" } }` | `{ "accessToken": "…", "refreshToken": "…", "expiresAt": "RFC3339", "deviceId": "opaque" }` |
| Refresh | `POST /api/watch/auth/refresh` | `{ "refreshToken": "…", "deviceId": "opaque" }` | rotated token tuple; old refresh token becomes unusable |
| Logout/revoke | `DELETE /api/watch/devices/{deviceId}/session` | no body | `204` after session, push token, and standalone routing are revoked |
| Device registration | `PUT /api/watch/devices/{deviceId}` | `{ "platform": "watchos", "app": "boreal-dialer", "appVersion": "…" }` | authoritative device record |
| Watch APNs token | `PUT /api/watch/devices/{deviceId}/push-token` | `{ "pushType": "standard", "token": "hex", "environment": "sandbox|production" }` | `{ "registrationId": "opaque", "updatedAt": "RFC3339" }` |
| Remove APNs token | `DELETE /api/watch/devices/{deviceId}/push-token` | no body | `204` |
| Contacts | `GET /api/watch/contacts?q=…&line=BF&limit=10&cursor=…` | no body | `{ "items": [{ "id": "…", "name": "…", "company": "…", "primaryPhone": "+…" }], "nextCursor": null }` |
| Recent calls | `GET /api/watch/calls/recent?line=BF&limit=25&cursor=…` | no body | bounded items containing `id`, E.164 `number`, optional `name`, `direction`, `occurredAt`, and `line` |
| Outbound bridge | `POST /api/telephony/watch/calls` | `{ "destination": "+…", "line": "BF", "contactId": "optional" }` | `{ "callId": "opaque", "status": "requesting", "version": 1 }` |
| Bridge status | `GET /api/telephony/watch/calls/{callId}` | no body | `{ "callId": "…", "status": "…", "version": 2, "updatedAt": "RFC3339", "error": null }` |
| Cancel bridge | `DELETE /api/telephony/watch/calls/{callId}` | no body | terminal/current bridge state; never unconditional fake success |
| Standalone routing | `PUT /api/watch/devices/{deviceId}/standalone-routing` | `{ "enabled": true }` | `{ "enabled": true, "verifiedCallback": true }`; the callback number is never client supplied |

Bridge states are `requesting`, `waitingForCallback`, `bridging`, `ringing`,
`connected`, `ended`, and `failed`. State versions increase monotonically;
clients ignore older status responses. Only the server/provider may assert
`connected`. Cancellation is valid before a terminal state and is idempotent.

### Notification payload

Watch notifications use standard APNs only. The custom payload is
`{ "schema": 1, "type": "client_message|staff_message|task|meeting|missed_call|voicemail|stage_change|call_status", "id": "opaque", "callId": "optional", "callStatus": "optional", "version": 2 }`.
The `aps.category` must be one of `MESSAGE`, `TASK`, `MEETING`, or
`MISSED_CALL`; secrets and sensitive CRM/financial fields are forbidden.

### Errors and idempotency

Non-2xx responses use
`{ "error": { "code": "stable_machine_code", "message": "safe text", "retryable": false, "requestId": "opaque" } }`.
Required codes include `unauthenticated`, `forbidden`, `invalid_request`,
`invalid_destination`, `callback_not_verified`, `not_found`, `conflict`,
`rate_limited`, `provider_unavailable`, and `server_unavailable`. A repeated
mutation with the same principal, route, and idempotency key returns the same
result (including `callId`) for at least 24 hours; reuse with a different body
returns `409 conflict`. Server-generated IDs, cursors, and APNs tokens are
opaque and must not be logged in plaintext.
