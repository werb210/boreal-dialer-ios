#!/bin/bash
# BOREAL_DIALER_v529 - keep the concurrency fixes in place.
set -euo pipefail
grep -q "final class FaceIDSignIn: Sendable" Sources/Auth/FaceIDSignIn.swift
! grep -q "@preconcurrency PKPushRegistryDelegate" Sources/Voice/PushManager.swift
grep -q "VoiceManager.shared.finishRegistration(token: token, failure: failure)" Sources/Voice/VoiceManager.swift
! grep -q "\[weak self\] error in" Sources/Voice/VoiceManager.swift
test ! -f UI/Calls/IncomingCallController.swift
echo "OK: v529 concurrency fixes present"
