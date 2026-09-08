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
