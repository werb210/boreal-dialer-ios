#!/usr/bin/env bash
# BOREAL_DIALER_WATCH_INCALL_v1
set -euo pipefail
python3 - <<'PY'
import sys
checks = [
    ("Sources/WatchShared/WatchMessage.swift", "WatchInCallMessage", "shared in-call payload missing"),
    ("Sources/WatchShared/WatchMessage.swift", "inCallKey", "shared in-call key missing"),
    ("Watch/WatchEventStore.swift", "func sendInCallControl", "watch cannot emit controls"),
    ("Watch/WatchRootView.swift", "sendInCallControl(muted ? .mute : .unmute)", "mute button not wired"),
    ("Watch/WatchRootView.swift", "sendInCallControl(.dtmf", "keypad not wired"),
    ("Sources/Voice/WatchBridge.swift", "WatchInCallMessage", "phone does not receive controls"),
    ("Sources/Voice/InCallControlRelay.swift", "/dtmf", "relay does not call the DTMF endpoint"),
    ("Sources/Voice/InCallControlRelay.swift", "/mute", "relay does not call the mute endpoint"),
    # v1 shipped fields nothing ever populated; mute no-opped in silence.
    ("Sources/Voice/InCallControlRelay.swift", "session?.conferenceId", "relay is not reading live conference state"),
    ("Sources/Voice/InCallControlRelay.swift", "APIConfig.BASE_URL", "relay uses a base URL that does not exist"),
]
bad = [f"{p}: {w}" for p, n, w in checks if n not in open(p).read()]
if bad:
    print("FAIL: watch in-call chain broken")
    [print("  -", b) for b in bad]
    sys.exit(1)
print("OK: wrist -> phone -> BF-Server for mute and DTMF")
PY
