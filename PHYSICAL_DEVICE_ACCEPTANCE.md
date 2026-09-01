# Physical-device acceptance (not yet executed)

Record device/iOS/build/network/date and change `[ ]` to `[x]` only after observation.

## Outgoing
- [ ] Wi-Fi  - [ ] cellular  - [ ] Bluetooth/AirPods  - [ ] speaker/receiver
- [ ] mute/unmute  - [ ] hold/resume  - [ ] DTMF  - [ ] remote hangup
## Incoming
- [ ] foreground  - [ ] background  - [ ] locked  - [ ] terminated
- [ ] caller cancellation  - [ ] reject  - [ ] answer  - [ ] remote hangup
## Network
- [ ] Wi-Fi → cellular during call  - [ ] cellular → Wi-Fi  - [ ] temporary loss/recovery
## Account and line
- [ ] logout prevents former-user calls  - [ ] login re-registers
- [ ] token refresh produces one registration  - [ ] BF/BI/SLF switch; active call keeps captured line
## Deep links
- [ ] Portal → phone, terminated/foreground/background  - [ ] Portal → contact context
- [ ] active call is not replaced  - [ ] default does not auto-dial

Production PushKit/APNs background and terminated behavior requires real credentials, paid provisioning, Twilio configuration, and a physical device; simulator/unit results are not evidence of delivery.
