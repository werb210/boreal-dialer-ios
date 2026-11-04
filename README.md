# Boreal iOS Dialer

Two-device Apple product: a native **iPhone-only** Twilio Voice dialer and an independent watchOS application foundation. There is no iPad product target.

## Status

**Code ready:** the canonical call lifecycle has one CallKit owner; VoIP and ordinary APNs paths/token types are separate; incoming calls use the Twilio invite UUID; PushKit registration is idempotent; logout unregisters Twilio; deep links are validated and retained across auth bootstrap; credentials are held in Keychain.

**External validation required:** application call-lifecycle code is complete, but production PushKit/APNs physical-device validation is pending paid Apple Developer provisioning and the real Apple/Twilio credential chain. Nothing in this repository is a production credential. See [APPLE_RELEASE_SETUP.md](APPLE_RELEASE_SETUP.md) and [PHYSICAL_DEVICE_ACCEPTANCE.md](PHYSICAL_DEVICE_ACCEPTANCE.md).

The iPhone retains native Twilio VoIP, PushKit, and CallKit. The Watch runs without an installed/available iPhone, registers directly for ordinary APNs, restores its own Keychain session, uses direct `URLSession` networking, and offers Dial, Contacts, Recents, and Notifications surfaces. WatchConnectivity is only a nearby-iPhone optimization for enrollment/state and companion control of an iPhone-owned call.

Twilio Voice does not provide a watchOS client SDK, so the Watch target neither imports nor links it. Standalone Watch audio is prepared through an abstract server-mediated cellular callback/bridge architecture; its server component is not implemented and the client clearly reports the capability unavailable rather than faking a call. See [Watch server requirements](WATCH_SERVER_REQUIREMENTS.md), [call contract](WATCH_CALL_SERVER_CONTRACT.md), and [standalone acceptance plan](WATCH_STANDALONE_ACCEPTANCE.md).

## Android (BOREAL_ANDROID_DIALER_v1)

`android/` is the Android dialler: a native app (Java, its own Gradle project) for Android phones and tablets, the
twin of the iPhone app. The Android staff portal (BF-portal `android/`) has no calling engine of its own; its Call
buttons open this app with `borealdialer://call?phone=...`, so one phone has one Twilio registration and never rings
twice.

| iPhone dialler | Android dialler |
| --- | --- |
| Text-code sign-in (`/api/auth/otp/start`, `/api/auth/otp/verify`) | The same |
| PushKit VoIP push + CallKit | Twilio FCM data message + Android Telecom (self-managed ConnectionService), full-screen call screen on the lock screen, foreground service during a call |
| `POST /api/voice/token` with the line | Same route with `app: "dialer-android"` (BF-Server `TWILIO_PUSH_CREDENTIAL_SID_ANDROID`, a Twilio push credential of type FCM) |
| `POST /api/staff/push-token` `app: "dialer-ios"` (APNs) | Same route, `app: "dialer-android"`, the Firebase token |
| Lines BF, BI, SLF, Keystone | The same four lines (X-Silo) |
| Keypad, Recents, Contacts, Messages (texts), Voicemail | The same five tabs, on `/api/voice/recent-calls`, `/api/crm/contacts`, `/api/communications/sms`, `/api/crm/voicemails` |
| Watch, widgets, Live Activity, CarPlay, team chat, calendar | Not on Android yet |

Build and test on the Android Studio emulator (Todd has no Android phone):

1. Download `android-dialler-debug-apk` from the latest "Android dialler" run in GitHub Actions, or open `android/`
   in Android Studio and press Run.
2. Drag the APK onto a running emulator (a "Google Play" system image, Android 8.0 or later).
3. Sign in with your staff mobile number; the code arrives on that phone by text.

Placing calls, recent calls, contacts, texts and voicemail all work on the emulator (it uses the computer's
microphone). Incoming calls and alerts need a build made with the `GOOGLE_SERVICES_JSON` secret.

CI: `.github/workflows/android.yml` runs the unit tests and builds a debug APK and an unsigned release bundle (AAB) on
every pull request that touches `android/`. Run it by hand ("Run workflow") for the signed bundle and the Google Play
upload.

## Architecture and contracts
- [Canonical ownership](CALL_ARCHITECTURE.md)
- [Native API audit](DIALER_API_CONTRACT.md)
- [Cross-platform contract](CROSS_PLATFORM_DIALER_CONTRACT.md)

The app bundle ID is `com.borealfinancial.dialer`; its registered fallback link forms are `borealdialer://call?phone=...` and `borealdialer://call?contactId=...`. Links prefill by default; only explicit validated `start=true` can request immediate action. A normal APNs server-registration contract does not yet exist and is documented rather than fabricated.

## Development
Generate the Xcode project with XcodeGen, resolve dependencies, then run the `BorealDialer` scheme/tests on macOS. SwiftPM targets iOS 15+; the generated app currently targets iOS 16+.
