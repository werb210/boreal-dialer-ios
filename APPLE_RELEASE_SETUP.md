# Apple and Twilio release setup

This product has two Apple targets. Preserve the project-defined identifiers: iPhone `financial.boreal.dialer` and Watch `financial.boreal.dialer.watchkitapp`.

## iPhone target

1. Register/confirm the iPhone App ID and signing profile. Enable Push Notifications for ordinary APNs and VoIP PushKit.
2. Enable the configured background modes: Voice over IP, remote notifications, and audio during an active call. Validate microphone usage disclosure and iPhone-only device family.
3. Configure Twilio Programmable Voice with the TwiML App/server URL, iOS VoIP Push Credential for the exact bundle/environment, incoming routing, access-token issuer, and staff identity mapping. Keep secrets outside the repository.
4. Confirm standard APNs and PushKit tokens are registered separately once the documented server device-registration contract exists.

## Independent Watch target

1. Register/confirm the Watch App ID/profile and its relationship to the iPhone app. Verify `WKRunsIndependentlyOfCompanionApp=YES` (“Supports Running Without iOS App Installation”).
2. Enable Push Notifications for the Watch App ID and provision its `aps-environment`. It uses ordinary APNs—not iPhone token forwarding and not VoIP PushKit.
3. Confirm Keychain access, HTTPS networking, notification categories, and any justified watchOS background capability. Do not configure permanent execution or deprecated complication pushes.
4. Implement and deploy the server contracts in `WATCH_SERVER_REQUIREMENTS.md`, then test direct Watch APNs, authentication, Wi-Fi/cellular API access, device revocation, and server bridge on physical cellular hardware.
5. Verify the Watch binary contains no TwilioVoice framework or unsupported iOS-only frameworks.

## Shared release controls

Generate a production APNs authentication key under controlled secret storage; never commit `.p8` material. Verify Release uses HTTPS production configuration, no localhost/mock identity/token, and production entitlements supplied by archive signing. Validate cookies server-side as `Secure`, `HttpOnly`, HTTPS-only, with appropriate `SameSite` behavior. Do not add Associated Domains until the HTTPS domain/AASA contract is confirmed.
