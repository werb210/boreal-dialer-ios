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
