#!/usr/bin/env bash
# BOREAL_DIALER_WATCH_LINK_COPY_v2
# SwiftUI views that exist on iOS but are marked unavailable on watchOS. Using
# one compiles fine in an editor and fails only on the macOS runner.
set -euo pipefail

python3 - <<'PY'
import glob, re, sys

BANNED = {
    "DisclosureGroup": "unavailable on watchOS - use NavigationLink to a sub-screen",
    "Table": "unavailable on watchOS",
    "OutlineGroup": "unavailable on watchOS",
    "ContextMenu": "unavailable on watchOS",
    "TabView": "available but severely limited on watchOS - verify before use",
}

failures = []
for path in glob.glob("Watch/**/*.swift", recursive=True):
    src = open(path).read()
    for line_no, line in enumerate(src.splitlines(), 1):
        if line.lstrip().startswith("//"):
            continue
        for name, why in BANNED.items():
            if re.search(rf"\b{name}\b\s*[({{]", line):
                failures.append(f"{path}:{line_no}: {name} - {why}")

if failures:
    print("FAIL: watchOS-unavailable SwiftUI API in the Watch target")
    for f in failures:
        print("  -", f)
    sys.exit(1)
print("OK: no watchOS-unavailable SwiftUI API in Watch/")
PY
