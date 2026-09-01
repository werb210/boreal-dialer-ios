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

`/voice/calls/active`, `/voice/presence`, `/auth/device-token`, and `/voice/register-voip` are documented stale/nonexistent routes and are not called. There is **no verified ordinary APNs token registration endpoint**. Required future server contract: authenticated registration/revocation carrying an APNs token plus platform/environment, returning success; it is needed for `client_message`/`stage_change`. No client request is made until that contract exists.
