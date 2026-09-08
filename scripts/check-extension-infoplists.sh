#!/usr/bin/env bash
# BOREAL_DIALER_BLOCK_v211_WIDGET_INFOPLIST_v1
# An app-extension whose Info.plist has no NSExtension dictionary builds and
# links cleanly, then fails at install with "extensionDictionary must be set in
# placeholder attributes" -- six minutes into a macOS run. Catch it here.
set -euo pipefail

python3 - <<'PY'
import re, sys

spec = open("project.yml").read()
targets = spec.split("\ntargets:\n", 1)[1] if "\ntargets:\n" in spec else spec
blocks = re.split(r"\n  (?=\w[\w-]*:\n)", "\n" + targets)

failures = []
for block in blocks:
    name = block.strip().split(":", 1)[0].strip()
    if not name or "type: app-extension" not in block:
        continue
    if "NSExtensionPointIdentifier" not in block:
        failures.append(f"{name}: no NSExtensionPointIdentifier")
        continue
    if re.search(r"^\s*GENERATE_INFOPLIST_FILE:\s*YES", block, re.M):
        failures.append(f"{name}: GENERATE_INFOPLIST_FILE=YES discards the NSExtension dictionary")
    if re.search(r"^\s*INFOPLIST_KEY_NSExtension", block, re.M):
        failures.append(f"{name}: INFOPLIST_KEY_NSExtension* is not a supported build setting")

if failures:
    print("FAIL: app-extension Info.plist problems")
    for f in failures:
        print("  -", f)
    sys.exit(1)
print("OK: every app-extension declares an extension point")
PY
