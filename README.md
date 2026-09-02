# Boreal iOS Dialer

Two-device Apple product: a native **iPhone-only** Twilio Voice dialer and an independent watchOS application foundation. There is no iPad product target.

## Status

**Code ready:** the canonical call lifecycle has one CallKit owner; VoIP and ordinary APNs paths/token types are separate; incoming calls use the Twilio invite UUID; PushKit registration is idempotent; logout unregisters Twilio; deep links are validated and retained across auth bootstrap; credentials are held in Keychain.

**External validation required:** application call-lifecycle code is complete, but production PushKit/APNs physical-device validation is pending paid Apple Developer provisioning and the real Apple/Twilio credential chain. Nothing in this repository is a production credential. See [APPLE_RELEASE_SETUP.md](APPLE_RELEASE_SETUP.md) and [PHYSICAL_DEVICE_ACCEPTANCE.md](PHYSICAL_DEVICE_ACCEPTANCE.md).

The iPhone retains native Twilio VoIP, PushKit, and CallKit. The Watch runs without an installed/available iPhone, registers directly for ordinary APNs, restores its own Keychain session, uses direct `URLSession` networking, and offers Dial, Contacts, Recents, and Notifications surfaces. WatchConnectivity is only a nearby-iPhone optimization for enrollment/state and companion control of an iPhone-owned call.

Twilio Voice does not provide a watchOS client SDK, so the Watch target neither imports nor links it. Standalone Watch audio is prepared through an abstract server-mediated cellular callback/bridge architecture; its server component is not implemented and the client clearly reports the capability unavailable rather than faking a call. See [Watch server requirements](WATCH_SERVER_REQUIREMENTS.md), [call contract](WATCH_CALL_SERVER_CONTRACT.md), and [standalone acceptance plan](WATCH_STANDALONE_ACCEPTANCE.md).

## Architecture and contracts
- [Canonical ownership](CALL_ARCHITECTURE.md)
- [Native API audit](DIALER_API_CONTRACT.md)
- [Cross-platform contract](CROSS_PLATFORM_DIALER_CONTRACT.md)

The app bundle ID is `financial.boreal.dialer`; its registered fallback link forms are `borealdialer://call?phone=...` and `borealdialer://call?contactId=...`. Links prefill by default; only explicit validated `start=true` can request immediate action. A normal APNs server-registration contract does not yet exist and is documented rather than fabricated.

## Development
Generate the Xcode project with XcodeGen, resolve dependencies, then run the `BorealDialer` scheme/tests on macOS. SwiftPM targets iOS 15+; the generated app currently targets iOS 16+.
