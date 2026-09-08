#!/usr/bin/env bash
# BOREAL_DIALER_BLOCK_v212_COMMIT_WIDGET_PLIST_v1
set -euo pipefail

python3 - <<'PY'
import os, re, sys

spec = open("project.yml").read()
paths = re.findall(r"^\s+path:\s+(\S+\.(?:plist|entitlements))\s*$", spec, re.M)
missing = [p for p in sorted(set(paths)) if not os.path.isfile(p)]

if missing:
    print("FAIL: project.yml references files that are not committed")
    for p in missing:
        print("  -", p)
    print("  Xcode falls back to an empty plist; app extensions then fail to install.")
    sys.exit(1)
print(f"OK: all {len(set(paths))} referenced plist/entitlements files are committed")
PY

python3 - <<'PY'
import plistlib, sys
# BOREAL_DIALER_BLOCK_v213_WATCH_APP_GROUP_v1
# Existence is not enough: XcodeGen leaves an already-committed entitlements
# file alone, so project.yml properties and the file on disk drift apart with
# no error anywhere. Watch/BorealWatch.entitlements declared the group in
# project.yml and lacked it on disk, which would have made every cross-target
# UserDefaults(suiteName:) read return nil at runtime.
GROUP = "group.financial.boreal.dialer"
failures = []
for path in ["Config/BorealDialer.entitlements",
             "Watch/BorealWatch.entitlements",
             "LiveActivity/BorealCallLiveActivity.entitlements",
             "WatchWidget/BorealWatchWidget.entitlements"]:
    groups = plistlib.load(open(path, "rb")).get("com.apple.security.application-groups", [])
    if GROUP not in groups:
        failures.append(f"{path}: missing {GROUP}")
if failures:
    print("FAIL: app-group entitlement drift")
    for f in failures:
        print("  -", f)
    sys.exit(1)
print("OK: app group present in every target that declares it")
PY
