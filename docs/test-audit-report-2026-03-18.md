# Test & API Audit Report (2026-03-18)

## Scope
- Repository-wide runnable tests/checks.
- Static contract review for APIs/routes/endpoints with focus on OTP and calling flows.
- No code fixes applied.

## Commands Run
1. `npm test`
2. `npm run lint`
3. `npm run typecheck`
4. `npx vitest run --config packages/dialer-web/vitest.config.ts` (repo root)
5. `npx vitest run --config vitest.config.ts` (from `packages/dialer-web`)
6. `swift test`

## Results Summary
- PASS: server Node tests (`npm test`) – 3/3 passing.
- PASS: ESLint (`npm run lint`).
- PASS: TypeScript typecheck (`npm run typecheck`).
- FAIL: web test discovery at repo root (config include path mismatch from root execution context).
- FAIL: web telephony unit tests (3 failures in `voiceDevice.test.ts`).
- FAIL: Swift package tests due to inability to clone Twilio Conversations dependency in this environment.

## Detailed Issues Found

### 1) Web unit tests are broken by mock/export mismatch (calling stack regression)
- `voiceDevice.ts` imports both `fetchVoiceToken` and `getVoiceToken`, and initialization path calls `getVoiceToken()`.
- `voiceDevice.test.ts` only mocks `fetchVoiceToken` from `../../services/twilioTokenService`.
- Result: all 3 tests in `voiceDevice.test.ts` fail before assertions with missing mocked export error for `getVoiceToken`.

Impact:
- Core dialer voice-device lifecycle tests are red; token initialization and refresh logic in telephony path is not reliably validated by CI.

Evidence files:
- `packages/dialer-web/src/telephony/services/voiceDevice.ts`
- `packages/dialer-web/src/telephony/services/voiceDevice.test.ts`

### 2) Endpoint contract drift in web token service (routes mismatch)
- `getVoiceToken()` calls `GET /api/calls/token`.
- `fetchVoiceToken()` calls `GET /api/twilio/voice-token`.
- Server exposes `POST /api/voice/token`.

Impact:
- Depending on which token helper is used, clients can hit non-existent routes and fail to obtain Twilio access tokens.
- Calling and token refresh can fail at runtime even if tests pass elsewhere.

Evidence files:
- `packages/dialer-web/src/services/twilioTokenService.ts`
- `packages/dialer-server/src/server.js`
- `packages/dialer-web/src/services/twilioTokenService.test.ts`

### 3) Additional endpoint drift in web call logging/calling telemetry
- `callLogger.ts` posts to `/api/calls/log`.
- `deviceManager.ts` logs connect events to `/api/dialer/log`.
- Server does not expose either `/api/calls/log` or `/api/dialer/log` in current route table.

Impact:
- Call logging/telemetry requests likely 404 and silently degrade observability and auditing.

Evidence files:
- `packages/dialer-web/src/services/callLogger.ts`
- `packages/dialer-web/src/twilio/deviceManager.ts`
- `packages/dialer-server/src/server.js`

### 4) iOS app references OTP/auth endpoints that are absent in current server
- iOS `AuthService.login` posts to `POST api/auth/otp/verify`.
- iOS `AuthService.refreshToken` posts to `POST api/auth/refresh`.
- Server currently has JWT middleware and voice routes, but no `/api/auth/*` route definitions.

Impact:
- OTP verification and token refresh flows cannot succeed against this server as checked in.
- Authentication path for iOS is effectively blocked unless provided by another backend not present here.

Evidence files:
- `Core/Auth/AuthService.swift`
- `packages/dialer-server/src/server.js`

### 5) iOS calling API route set does not match server route set
iOS API layer uses several voice endpoints that are not present in the server:
- `POST api/voice/device-token`
- `POST api/voice/calls/answer`
- `POST api/voice/record/start`
- `POST api/voice/record/stop`
- `GET api/voice/calls/active`
- `POST api/voice/calls/log`

Server currently defines (relevant subset):
- `POST /api/voice/token`
- `POST /api/voice/presence/heartbeat`
- `POST /api/voice/call`
- `POST /api/voice/calls/start`
- `POST /api/voice/calls/end`
- `GET /api/voice/calls/:id`
- `POST /api/voice/status`
- `POST /api/voice/recording`

Impact:
- Significant cross-platform contract mismatch; inbound/outbound call control, recording, and active-call sync from iOS can fail with 404/unsupported route errors.

Evidence files:
- `Core/Networking/API.swift`
- `Core/Networking/NetworkManager.swift`
- `packages/dialer-server/src/server.js`

### 6) Authentication mode mismatch risk (Bearer JWT vs cookie/session expectations)
- Server `authMiddleware` requires Bearer JWT in `Authorization` header for non-webhook routes.
- Web `deviceManager.refreshToken` calls `/api/voice/token` with `credentials: "include"` but without attaching Bearer token itself.

Impact:
- If the surrounding web auth layer does not inject Authorization headers consistently, token refresh path can fail with 401.
- This is a contract risk between frontend auth state and backend requirements.

Evidence files:
- `packages/dialer-server/src/middleware/auth.js`
- `packages/dialer-web/src/twilio/deviceManager.ts`

### 7) Test command ergonomics issue for web package
- Running `npx vitest run --config packages/dialer-web/vitest.config.ts` from repo root reports "No test files found" because config include is `src/**/*.test.ts` and is interpreted from root.
- Running from `packages/dialer-web` correctly discovers tests.

Impact:
- CI/local test invocation from repo root can produce false-negative “no tests found” failures for web package.

Evidence files:
- `packages/dialer-web/vitest.config.ts`

## Notes on OTP/API/Calling coverage from this audit
- OTP and refresh routes are referenced by iOS but absent in current Node server route definitions.
- Voice/calling paths are partially implemented server-side, but route naming differs substantially from both iOS and parts of web clients.
- Current automated tests heavily cover server voice happy paths but do not catch many cross-client contract mismatches.
