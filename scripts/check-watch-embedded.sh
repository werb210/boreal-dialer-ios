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
