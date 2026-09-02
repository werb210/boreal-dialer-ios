# Physical Apple Watch standalone acceptance

All boxes are intentionally unchecked until performed on a provisioned cellular Apple Watch and production-like server/APNs environment.

## Installation
- [ ] Watch app installs with iPhone companion
- [ ] Watch app can run independently
- [ ] Watch app launches with iPhone powered off

## Network
- [ ] Direct API over Watch Wi-Fi
- [ ] Direct API over Watch cellular
- [ ] Transition Wi-Fi → cellular without requiring iPhone
- [ ] Offline and recovery states are accurate

## Authentication
- [ ] Standalone auth restore from Watch Keychain
- [ ] Token expiration refresh/re-authentication
- [ ] Invalid login differs from unavailable network
- [ ] Logout and sensitive-cache clearing without iPhone

## Notifications
- [ ] Direct Watch APNs notification with iPhone off
- [ ] Client/staff message
- [ ] Task
- [ ] Missed call
- [ ] Stage/application update if supported by server
- [ ] Meeting/voicemail where supported
- [ ] Notification tap routes correctly; malformed/unknown payload opens home
- [ ] Watch token is distinct from iPhone standard and VoIP tokens

## Contacts and recents
- [ ] Search over Watch cellular
- [ ] Search over Watch Wi-Fi
- [ ] Results are bounded and silo-authorized
- [ ] Server-authoritative recents refresh and bounded local cache

## Calling (blocked until documented server capability is implemented)
- [ ] Standalone call request over cellular
- [ ] Standalone call request over Wi-Fi
- [ ] Callback rings cellular Watch
- [ ] Destination bridge succeeds
- [ ] Correct Boreal line authorization
- [ ] Correct CRM call log
- [ ] Failure/cancellation is recoverable; duplicate tap creates one call
- [ ] Server-reported state is required before showing connected
- [ ] Incoming Boreal route rings Watch with iPhone powered off

## Companion optimization
- [ ] iPhone incoming Twilio call appears on Watch
- [ ] Answer
- [ ] Decline
- [ ] End when supported
- [ ] iPhone unavailable leaves standalone home/auth/API usable

Record device/watchOS versions, network path, APNs environment, server version, timestamps, and evidence for every completed item. Do not merge/release standalone calling based only on simulator or source tests.
