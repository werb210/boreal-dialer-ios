#!/usr/bin/env bash
# BOREAL_DIALER_WATCH_LINK_COPY_v1
# The auto-link chain spans three files in two targets. A break anywhere leaves
# the Watch on the manual-code fallback with no error, which is how it was
# recorded as "pairing code removed" while the code field was still shipping.
set -euo pipefail

python3 - <<'PY'
import sys

checks = [
    ("UI/Settings/AccountSheet.swift", "WatchBridge.shared.sendEnrollment", "phone does not send the enrollment code"),
    ("Sources/Voice/WatchBridge.swift", "func sendEnrollment", "bridge cannot transmit an enrollment"),
    ("Sources/WatchShared/WatchMessage.swift", "enrollKey", "shared enrollment key is missing"),
    ("Sources/WatchShared/WatchMessage.swift", "struct WatchEnrollMessage", "shared enrollment payload is missing"),
    ("Watch/WatchEventStore.swift", "WatchPayload.enrollKey", "watch does not listen for enrollments"),
    ("Watch/WatchEventStore.swift", "link(oneTimeCode: enroll.oneTimeCode", "watch receives the code but never links"),
]

failures = []
for path, needle, why in checks:
    try:
        if needle not in open(path).read():
            failures.append(f"{path}: {why}")
    except FileNotFoundError:
        failures.append(f"{path}: file missing")

if failures:
    print("FAIL: Watch auto-link chain is broken")
    for f in failures:
        print("  -", f)
    sys.exit(1)
print("OK: enrollment flows phone -> bridge -> watch -> link")
PY
