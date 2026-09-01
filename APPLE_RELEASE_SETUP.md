# Apple and Twilio release setup

Current app ID/bundle ID: `financial.boreal.dialer` (Watch companion: `financial.boreal.dialer.watchkitapp`). Preserve these identifiers.

After paid Apple Developer access is available:
1. Register/confirm both App IDs and signing teams/profiles. Enable **Push Notifications** for the dialer.
2. Enable Background Modes used by the target: **Voice over IP**, remote notifications, and audio for an active call. CallKit is framework functionality, not a separate capability.
3. Generate a production APNs authentication key/certificate under controlled secret storage. Never commit the `.p8` private key.
4. In Twilio Programmable Voice configure the TwiML App/server voice URL, iOS VoIP Push Credential linked to production APNs and the exact bundle/environment, incoming-number routing, access-token issuer, and staff identity mapping. Store Account SID/API key secret/Auth Token outside this repo.
5. Verify Release uses HTTPS production configuration, no localhost/mock/test identity/token, and production `aps-environment` supplied by release signing. The checked-in entitlement is development-only for local signing and must be validated in the archive.
6. Validate server cookies are `Secure`, `HttpOnly`, HTTPS-only, and have appropriate `SameSite` behavior. This is a server setting; no BF-Server change is included here.

Do not add Associated Domains until the HTTPS domain and AASA contract are confirmed. The custom scheme remains the fallback.
