#!/usr/bin/env bash
# BOREAL_DIALER_CI_SIMULATOR_v682 - prints the id of a simulator CI can build and test on.
# GitHub's macOS image (Xcode 26.6) can come without any simulator for the current runtime,
# so xcodebuild offers only the "Any iOS Simulator Device" placeholder and the run stops
# ("No iPhone simulator destination was offered"). When that happens this creates one,
# downloading the simulator runtime first if it is missing.
# Usage: ci-simulator.sh iOS|watchOS SCHEME DESTINATIONS_FILE
set -euo pipefail
PLATFORM="$1"; SCHEME="$2"; OUT="$3"
HERE="$(cd "$(dirname "$0")" && pwd)"
show() { xcodebuild -project BorealDialer.xcodeproj -scheme "$SCHEME" -showdestinations > "$OUT" 2>&1 || true; }

show
UDID="$(python3 "$HERE/ci_simulator.py" from-destinations "$OUT" "$PLATFORM")"
if [ -n "$UDID" ]; then echo "$UDID"; exit 0; fi

echo "No $PLATFORM simulator on this runner - creating one." >&2
RUNTIME="$(xcrun simctl list runtimes -j | python3 "$HERE/ci_simulator.py" runtime "$PLATFORM")"
if [ -z "$RUNTIME" ]; then
  echo "Downloading the $PLATFORM simulator runtime (this takes a few minutes)." >&2
  xcodebuild -downloadPlatform "$PLATFORM" >&2
  RUNTIME="$(xcrun simctl list runtimes -j | python3 "$HERE/ci_simulator.py" runtime "$PLATFORM")"
fi
[ -n "$RUNTIME" ] || { echo "No $PLATFORM simulator runtime could be installed." >&2; exit 1; }
DEVTYPE="$(xcrun simctl list runtimes -j | python3 "$HERE/ci_simulator.py" devicetype "$PLATFORM" "$RUNTIME")"
[ -n "$DEVTYPE" ] || { echo "The $PLATFORM runtime $RUNTIME supports no suitable device." >&2; exit 1; }
xcrun simctl create "CI $PLATFORM" "$DEVTYPE" "$RUNTIME" >&2

show
UDID="$(python3 "$HERE/ci_simulator.py" from-destinations "$OUT" "$PLATFORM")"
[ -n "$UDID" ] || { echo "Created a simulator but xcodebuild still offers none:" >&2; cat "$OUT" >&2; exit 1; }
echo "$UDID"
