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
