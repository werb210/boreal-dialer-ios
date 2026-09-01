# Cross-platform dialer contract

## Vocabulary
- **Auth:** authenticated staff identity; tokens are platform-secure and ephemeral where possible.
- **Lines:** `BF`, `BI`, `SLF`. A command captures its authorized line at creation.
- **Call command:** exactly one of E.164 `phone` or supported `contactId`, plus line/silo.
- **States:** `idle`, `ringing`, `connecting`, `connected`, `ended`, `failed`.
- **Actions:** `start`, `answer`, `reject`, `end`, `mute`, `unmute`, `hold`, `resume`, `DTMF`.
- **Call ID:** one stable logical UUID across invite, platform call UI, state and companion events.

## Links
`borealdialer://call?phone=<percent-encoded-E.164>` or `borealdialer://call?contactId=<ID>`. `start=true` is the only explicit immediate-call request; default is prefill/confirmation. Clients reject unknown schemes/routes/keys, duplicate keys, malformed phones, and IDs over 128 characters. Contact resolution depends on an existing authorized contact contract; no endpoint is implied. A future `https://<confirmed-domain>/dialer/call` may mirror this after domain confirmation and association-file deployment.

## Push
Incoming calls use iOS PushKit VoIP or Android FCM high-priority incoming-call messages and must be authenticated/validated by the voice provider. General staff notifications use ordinary APNs/FCM only. Push metadata cannot authorize a line, mutation, URL navigation, or outbound call.
