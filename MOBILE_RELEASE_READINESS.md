# Boreal Dialer mobile release readiness

## Supported product matrix

| Item | Status |
| --- | --- |
| Product | **Boreal Dialer** |
| iPhone | **Supported** |
| iPad | **Not supported** |
| Apple Watch | **Supported** |
| Android / Wear OS | **Not supported** |
| iPhone bundle ID | `financial.boreal.dialer` |
| Watch bundle ID | `financial.boreal.dialer.watchkitapp` |
| iPhone code state | Unsigned simulator build and unit tests verified by CI |
| Watch code state | Unsigned Watch simulator build and Watch unit tests verified by CI |

CI resolves concrete iPhone and watchOS simulator destinations from
`xcodebuild -showdestinations`; it does not depend on a model name or OS version.
Static gates preserve device families 1 (iPhone) and 4 (Watch), independent
Watch operation, the bundle IDs, and the absence of Watch Twilio linkage.

## External release prerequisites

An **Apple Developer account is still required** for:

- production signing and App IDs;
- iPhone and Watch provisioning;
- APNs and the PushKit/VoIP capability;
- production push credentials;
- TestFlight;
- physical iPhone deployment; and
- physical Watch deployment.

**Twilio still requires** a production iOS VoIP Push Credential and production
server configuration. TwilioVoice remains an iPhone-only dependency. The Watch
uses standard APNs and carrier/server bridge semantics; it does not host Twilio
media.

## Standalone Watch readiness boundary

The independent-Watch client architecture is present, uses HTTPS and Watch
Keychain storage, and treats WatchConnectivity only as an optimization. It does
not establish that BF-Server implements the required contract.

Standalone Watch still requires server implementation and integration testing
of:

- independent Watch authentication/session refresh and revocation;
- Watch device and standard APNs registration;
- bounded, authorized contacts and recents;
- outbound bridge creation, authoritative status, and cancellation;
- standalone incoming routing and trusted callback handling; and
- device-specific and account-wide revocation.

Until those capabilities are implemented and verified in BF-Server, standalone
Watch calling is **not production-complete**. The client must continue returning
an unavailable state rather than inventing an endpoint, URL, contact/recent,
bridge, or successful/connected state. See
[`WATCH_SERVER_REQUIREMENTS.md`](WATCH_SERVER_REQUIREMENTS.md) and
[`WATCH_CALL_SERVER_CONTRACT.md`](WATCH_CALL_SERVER_CONTRACT.md).

## Preserved security and call boundaries

- iPhone and Watch session secrets use their respective Keychains and logout
  clears the local session.
- ATS remains enabled; production API traffic is HTTPS with no arbitrary-load
  exception.
- PushKit accepts only genuine incoming Twilio VoIP call payloads. Ordinary
  messages, tasks, meetings, CRM events, voicemail notices, and status updates
  use standard APNs with lock-screen-safe payloads.
- `VoiceEngine` remains the single CallKit provider owner.
