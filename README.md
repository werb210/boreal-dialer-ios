# Boreal iOS Dialer

This is the initial scaffold for the Boreal native iOS dialer app.

## Overview

- Outbound calling UI
- Twilio Voice integration (token pending)
- SMS UI scaffold
- Local mock support
- Modular architecture

## Required Capabilities

- Enable "Background Modes"
- Enable "Voice over IP"
- Enable "Push Notifications"
- Enable "CallKit" capability

## Twilio Voice Requirements

- Twilio Programmable Voice must be enabled
- Server must expose `POST /api/voice/token`
- Twilio App SID required
- TwiML App configured with Voice URL

## VoIP Setup Requirements (Future Production)

- Enable "Push Notifications"
- Enable "Background Modes"
- Enable "Voice over IP"
- Add PushKit entitlement
- Upload APNs VoIP certificate to Twilio Console

Server must support:

`POST /api/voice/register-voip`

Body:

```
{
  deviceToken: string,
  userId: string
}
```
