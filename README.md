# Boreal iOS Dialer

Native iPhone/iPad dialer with Twilio Voice, PushKit, CallKit, CRM caller resolution, BF/BI/SLF line selection, conference fallback, call history, and Watch companion messaging.

## Status

**Code ready:** the canonical call lifecycle has one CallKit owner; VoIP and ordinary APNs paths/token types are separate; incoming calls use the Twilio invite UUID; PushKit registration is idempotent; logout unregisters Twilio; deep links are validated and retained across auth bootstrap; credentials are held in Keychain.

**External validation required:** application call-lifecycle code is complete, but production PushKit/APNs physical-device validation is pending paid Apple Developer provisioning and the real Apple/Twilio credential chain. Nothing in this repository is a production credential. See [APPLE_RELEASE_SETUP.md](APPLE_RELEASE_SETUP.md) and [PHYSICAL_DEVICE_ACCEPTANCE.md](PHYSICAL_DEVICE_ACCEPTANCE.md).

## Architecture and contracts
- [Canonical ownership](CALL_ARCHITECTURE.md)
- [Native API audit](DIALER_API_CONTRACT.md)
- [Cross-platform contract](CROSS_PLATFORM_DIALER_CONTRACT.md)

The app bundle ID is `financial.boreal.dialer`; its registered fallback link forms are `borealdialer://call?phone=...` and `borealdialer://call?contactId=...`. Links prefill by default; only explicit validated `start=true` can request immediate action. A normal APNs server-registration contract does not yet exist and is documented rather than fabricated.

## Development
Generate the Xcode project with XcodeGen, resolve dependencies, then run the `BorealDialer` scheme/tests on macOS. SwiftPM targets iOS 15+; the generated app currently targets iOS 16+.
