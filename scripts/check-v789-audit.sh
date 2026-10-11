#!/usr/bin/env bash
# BOREAL_DIALER_V789_AUDIT - audit round 2 stays fixed.
#  [178] every VoIP push reports to CallKit through CallKitReporter, synchronously
#  [187] the dead voice / auth / messaging code stays deleted
#  [6]   each shipped bundle has a privacy manifest declaring its required-reason APIs
#  [8]   every target's CFBundleVersion is CURRENT_PROJECT_VERSION
set -euo pipefail

python3 - <<'PY'
import os, plistlib, re, sys

fail = []

def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()

# [178] PushKit -> CallKit
push = read("Sources/Voice/PushManager.swift")
handler = push.split("didReceiveIncomingPushWith", 1)[1].split("\n}\n", 1)[0]
if "CallKitReporter.shared.handleVoIPPush" not in handler:
    fail.append("PushManager does not hand VoIP pushes to CallKitReporter")
if "DispatchQueue.main.async" in handler or "Task {" in handler or "Task { @MainActor" in handler:
    fail.append("PushManager hops queues before reporting to CallKit")
if "PKPushRegistry(queue: .main)" not in push:
    fail.append("PushKit registry must deliver on the main queue")
twilio = read("Sources/Voice/TwilioVoiceManager.swift")
invite = twilio.split("func callInviteReceived", 1)[1].split("func cancelledCallInviteReceived", 1)[0]
if "CallKitReporter.shared.receive(" not in invite:
    fail.append("TwilioVoiceManager.callInviteReceived bypasses CallKitReporter")
if "DispatchQueue.main.async" in invite:
    fail.append("TwilioVoiceManager reports the invite after an async hop")
engine = read("Sources/Voice/VoiceEngine.swift")
incoming = engine.split("func reportIncoming(", 1)[1].split("\n    }\n", 1)[0]
if "reportPlaceholder" not in incoming:
    fail.append("VoiceEngine.reportIncoming drops a call when not idle")
reporter = read("Sources/Voice/CallKitReporter.swift")
for needed in [".failed", ".unanswered", "invite.reject()", "push?.finish()"]:
    if needed not in reporter:
        fail.append(f"CallKitReporter is missing {needed}")
if not os.path.isfile("Tests/BorealDialerTests/CallKitReporterTests.swift"):
    fail.append("Tests/BorealDialerTests/CallKitReporterTests.swift is missing")

# [187] dead code
for dead in ["Sources/Voice/VoiceService.swift", "UI/Calls/IncomingCallView.swift",
             "Sources/Voice/TokenProvider.swift", "Sources/Services/TelephonyService.swift",
             "Sources/Messaging/SecureMessageStore.swift", "Sources/Auth/AuthManager.swift",
             "Sources/Voice/CallKitManager.swift", "Package.swift", "ios/Podfile"]:
    if os.path.exists(dead):
        fail.append(f"{dead} is dead code and was deleted in v789")
vm = read("Sources/Voice/VoiceManager.swift")
if re.search(r"extension VoiceManager\s*:[^{]*(CallDelegate|NotificationDelegate)", vm):
    fail.append("VoiceManager handles calls again; TwilioVoiceManager owns calls")

# [6] privacy manifests
spec = read("project.yml")
REQUIRED = {
    "Config/PrivacyInfo.xcprivacy": {"NSPrivacyAccessedAPICategoryUserDefaults": {"CA92.1", "1C8F.1"},
                                     "NSPrivacyAccessedAPICategoryFileTimestamp": {"C617.1"}},
    "Watch/PrivacyInfo.xcprivacy": {"NSPrivacyAccessedAPICategoryUserDefaults": {"1C8F.1"}},
    "WatchWidget/PrivacyInfo.xcprivacy": {"NSPrivacyAccessedAPICategoryUserDefaults": {"1C8F.1"}},
    "LiveActivity/PrivacyInfo.xcprivacy": {"NSPrivacyAccessedAPICategoryUserDefaults": {"1C8F.1"}},
}
for path, apis in REQUIRED.items():
    if not os.path.isfile(path):
        fail.append(f"{path} is missing")
        continue
    if f"- path: {path}" not in spec:
        fail.append(f"project.yml does not bundle {path}")
    declared = {}
    for entry in plistlib.load(open(path, "rb")).get("NSPrivacyAccessedAPITypes", []):
        declared.setdefault(entry.get("NSPrivacyAccessedAPIType"), set()).update(entry.get("NSPrivacyAccessedAPITypeReasons", []))
    for api, reasons in apis.items():
        if not reasons <= declared.get(api, set()):
            fail.append(f"{path}: {api} must declare {sorted(reasons)}")

# [8] one build number
if not re.search(r"^settings:\n  base:\n    CURRENT_PROJECT_VERSION:", spec, re.M):
    fail.append("project.yml must set CURRENT_PROJECT_VERSION at project level")
targets = spec.split("\ntargets:\n", 1)[1]
for block in re.split(r"\n  (?=\w[\w-]*:\n)", "\n" + targets):
    name = block.strip().split(":", 1)[0].strip()
    if not name or "\n    info:\n" not in block:
        continue
    if "CFBundleVersion: $(CURRENT_PROJECT_VERSION)" not in block:
        fail.append(f"{name}: CFBundleVersion must be $(CURRENT_PROJECT_VERSION)")
ci = read(".github/workflows/ci.yml")
if "BUILD_NUMBER: ${{ github.run_number }}" not in ci:
    fail.append("ci.yml does not derive the build number from GITHUB_RUN_NUMBER")
for block in re.findall(r"xcodebuild \\\n(?:.*\\\n)*?.*(?:build-for-testing|test-without-building)[^\n]*", ci):
    if 'CURRENT_PROJECT_VERSION="$BUILD_NUMBER"' not in block:
        fail.append("an xcodebuild build/test in ci.yml does not pass CURRENT_PROJECT_VERSION")
        break

if fail:
    print("FAIL: v789 audit")
    for f in fail:
        print("  -", f)
    sys.exit(1)
print("OK: v789 audit round 2 - CallKit reporting, dead code, privacy manifests, build numbers")
PY
