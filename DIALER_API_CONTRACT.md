# Dialer API contract audit

All paths are relative to the HTTPS environment base URL and use the Keychain-held staff bearer token through `APIClient` (plus `X-Silo`). Cookie handling remains enabled; server cookies must be `Secure`, `HttpOnly`, HTTPS-only and use native-client-appropriate `SameSite`. The app does not copy cookies to preferences.

| Method/path | Request | Response | Used by | Failure behavior |
|---|---|---|---|---|
| `POST /voice/token` | JSON `{line}` in `API`; legacy callers may send no body; authenticated | `{token: String}` | registration/outgoing SDK adapter | no registration/call; recoverable error |
| `POST /voice/status` | `{callStatus}` | success body ignored | legacy voice status reporting | logged in debug; call cleanup continues |
| `POST /telephony/presence` | `{status, source:"dialer"}` | success body ignored | registration/call/presence | best effort |
| `POST /communications/call-events` | `{duration,status,number?,callSid?}` | success body ignored | idempotent lifecycle completion boundary | queued/best effort; UI ends |
| `POST /communications/sms` | `{to,message}` | success body ignored | SMS | throws to UI/offline queue |
| `POST /voice/calls` | `{to,line}` or `{staffIdentity,line}` | conference/call identifiers | outbound and internal conference setup | direct Twilio fallback for external calls; internal call fails safely |
| `DELETE /voice/conferences/{id}` | none | success body ignored | conference cleanup | best effort |

`/voice/calls/active`, `/voice/presence`, `/auth/device-token`, and `/voice/register-voip` are documented stale/nonexistent routes and are not called. Ordinary APNs alert pushes (BOREAL_DIALER_v820_WATCH, BF-Server v820): `POST /staff/push-token {token, environment: "production"|"sandbox", app: "dialer-ios"}` after sign-in and on token change, `DELETE /staff/push-token {token}` on sign-out. Alert categories: MISSED_CALL, VOICEMAIL, CLIENT_MESSAGE, SMS, HANDOFF (top-level `type`, optional `contactId`, `phone`, `threadKind`).

BOREAL_DIALER_v821: `GET /calls/{callSid}/summary` -> `{status: pending|ready|none, summary?, nextSteps?, taskId?, contactId?, contactName?}` (polled every 5 s for up to 2 min); `GET /voice/caller-card?phone=<E.164>` -> `{found, contactId?, name?, company?, stage?, applicationId?, lastNote?, lastContactAt?, tags?}` plus invite customParameters `callerName`, `callerCompany`, `callerStage`, `contactId`; VOICEMAIL alerts carry top-level `voicemailId`; `GET /templates/quick?channel=sms` -> `{items: [{id, name, body, isSnippet}]}` (iPhone and Watch, cached a day); `GET /staff/next-follow-up`; `GET /staff/missed-summary`; `GET`/`PUT /staff/call-hours` `{enabled, timezone, weekly, urgentPassthrough}`. Optional: aps `filter-criteria` `"client"`/`"internal"` lets the Boreal Dialer Focus filter hide internal pushes while the app is in the background.

BOREAL_DIALER_v822_CARPLAY (BF-Server v822): SMS and CLIENT_MESSAGE alerts carry aps `mutable-content: 1` and top-level `senderName` (<=60 chars, omitted for an unknown texter). The BorealDialerNotificationService extension attaches the sender (name, `phone` or `contactId`) as an INSendMessageIntent so Siri reads them aloud in CarPlay and on AirPods; Siri replies go out through `POST /sms/send` like the composer. CarPlay lists use the existing `/voice/recent-calls`, `/crm/voicemails` (+ `/:id/audio`) and `/telephony/quick-call`.
