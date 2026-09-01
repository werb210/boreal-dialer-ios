# Canonical call architecture

`BorealDialerApp` starts `PushManager`, `VoiceEngine`, and the connectivity services. The shipping SwiftUI dialer observes `VoiceEngine`; `CallManager` is a UI compatibility adapter. **`VoiceEngine` is the sole high-level lifecycle and sole `CXProvider` owner.** It owns CallKit state/actions, stable call UUID, UI state, audio controls, server completion, and Watch events. `TwilioVoiceManager` is the SDK adapter for calls/invites. `VoiceManager` owns only Twilio access-token/VoIP registration lifecycle and legacy API compatibility. `CallKitManager` and `VoIPPushManager` are provider/registry-free façades. `VoiceService` is legacy persistence code and does not own CallKit.

Flow: PushKit → `PushManager` → Twilio notification validation → `TwilioVoiceManager` invite → `VoiceEngine.reportIncoming` (same invite UUID) → CallKit/Watch. CRM naming occurs after reporting. V1 accepts one call; later invites are rejected.
