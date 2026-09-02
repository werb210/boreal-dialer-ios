# Standalone Watch call server contract

BF-Server now implements the authenticated standalone Watch callback bridge at `POST /api/telephony/watch/calls`, with status at `GET /api/telephony/watch/calls/{callId}` and cancellation at `DELETE /api/telephony/watch/calls/{callId}`. The client base URL already includes `/api`, so its paths omit that prefix.

A call request contains an E.164 `destination`, authorized `line` (`BF`, `BI`, or `SLF`), and optional `contactId`, plus an `Idempotency-Key`. It never contains a callback number. Server states are `requesting`, `waitingForCallback`, `bridging`, `ringing`, `connected`, `ended`, and `failed`; versioned server state is authoritative.

The server obtains the verified staff cellular callback number and bridges carrier media. The Watch does not carry Twilio audio. TwilioVoice, PushKit, and the existing CallKit flow remain iPhone-only. Watch notifications use standard APNs only.

Production credentials, Apple/APNs configuration, and provider configuration remain external deployment responsibilities. Physical cellular Apple Watch acceptance testing is required before release.
