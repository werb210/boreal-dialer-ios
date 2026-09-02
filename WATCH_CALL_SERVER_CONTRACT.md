# Standalone Watch call server contract

This is a **required server contract**, not an implemented BF-Server feature. The watchOS client contains no Twilio media SDK and must not report a call as connected without authoritative server status.

## Outbound bridge

`POST /api/telephony/watch/calls` (proposed; currently unavailable) requires staff authentication and device-session authorization.

```json
{ "destination": "+14035551234", "line": "BF", "contactId": "optional" }
```

The server must validate E.164 destination, staff silo permission, replay/idempotency, concurrency, and the Watch device session. It must obtain the trusted staff callback number from server-side configuration; a request-supplied callback number is forbidden. A successful response is:

```json
{ "callId": "opaque", "status": "initiating" }
```

The server calls the authorized staff cellular endpoint first. After the staff member answers on Apple Watch, it calls the destination, bridges both carrier legs, and writes the correct CRM contact/application call log. Errors must distinguish authentication, authorization, invalid destination, unavailable callback configuration, duplicate request, rate limit, and provider failure.

`GET /api/telephony/watch/calls/{callId}` (proposed; currently unavailable) returns only calls owned by the authenticated staff/device session. Status vocabulary is `requesting`, `waitingForCallback`, `ringing`, `connected`, `ended`, or `failed`, with an optional safe error code. `DELETE /api/telephony/watch/calls/{callId}` cancels setup or ends the bridge when possible. Mutations require an idempotency key.

Status can also arrive through ordinary APNs using an opaque call ID. Polling during setup must be bounded and stop on terminal status, timeout, backgrounding, or cancellation. The Watch must never infer `connected` merely from elapsed time.

## Incoming standalone routing

When explicitly enabled for an authorized Watch device, an incoming Boreal/Twilio call must route server-side to the trusted staff cellular number so the carrier call rings a cellular Apple Watch without iPhone involvement. A separate ordinary APNs notification may contain caller display name, company, Boreal line, and opaque call ID—never credentials or detailed CRM/financial data. The carrier call, not the notification or Watch app, owns audio.

## Security and lifecycle

The server is authoritative for BF/BI/SLF permission, callback destination, presence/routing eligibility, contact attribution, and call state. Audit call creation and state transitions. Revoking a device session disables new calls and direct pushes. Signing out must deregister that Watch token when the endpoint exists. iPhone Twilio/PushKit calling remains separate.
