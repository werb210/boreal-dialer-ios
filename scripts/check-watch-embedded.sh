#!/usr/bin/env bash
# BOREAL_DIALER_EMBED_WATCH_v375 - the iPhone app must embed the Watch app, or
# the phone never sees the Watch app as its companion and store builds ship
# without it.
set -euo pipefail
python3 - <<'PY'
import re, sys
text = open("project.yml", encoding="utf-8").read()
targets = text.split("\ntargets:\n", 1)[1]
m = re.search(r"(?ms)^  BorealDialer:\n(.*?)(?=^  [A-Za-z][A-Za-z0-9]*:\n|\Z)", targets)
if not m or "- target: BorealDialerWatch\n" not in m.group(1):
    print("::error::BorealDialer no longer embeds BorealDialerWatch")
    sys.exit(1)
print("OK: iPhone app embeds the Watch app")
PY

# BOREAL_DIALER_CI_NO_SDK_OVERRIDE_v377 - the iPhone build must not force an SDK,
# or the embedded Watch targets get compiled for iOS and the build fails.
python3 - <<'PY'
import re, sys
ci = open(".github/workflows/ci.yml", encoding="utf-8").read()
for block in re.findall(r"xcodebuild \\\n(?:.*\\\n)*?.*(?:build|test)[^\n]*", ci):
    if "-scheme BorealDialer \\" in block and "-sdk " in block:
        print("::error::the BorealDialer xcodebuild passes -sdk; embedded Watch targets would build for iOS")
        sys.exit(1)
print("OK: iPhone build lets each embedded target use its own SDK")
PY
