# Apple Watch server integration

BF-Server now provides Watch enrollment, link and rotating refresh sessions; device registration; standard APNs token registration; standalone routing; session revocation; bounded contact search and recents; and the standalone cellular callback bridge. Routes live below `/api`; clients configured with an `/api` base use `/watch/...` and `/telephony/watch/...` paths to avoid a duplicate prefix.

The Watch owns its independent Keychain session, connects directly over HTTPS, and treats WatchConnectivity only as a nearby-iPhone optimization. It uploads only a standard APNs token. It does not use PushKit or TwilioVoice, and standalone call media travels through BF-Server's server-mediated cellular bridge rather than through the Watch app.

Production credentials and Apple/APNs/provider configuration remain external and are not asserted complete by this repository. Physical testing on a cellular Apple Watch is still mandatory before release.
