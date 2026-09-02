#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

python3 - <<'PY'
from pathlib import Path
import re

text = Path("project.yml").read_text(encoding="utf-8")
targets = text.split("\ntargets:\n", 1)[1]

def target_block(name: str) -> str:
    match = re.search(rf"(?ms)^  {re.escape(name)}:\n(.*?)(?=^  [A-Za-z][A-Za-z0-9]*:\n|\Z)", targets)
    if not match:
        raise SystemExit(f"Required target {name} is missing")
    return match.group(1)

phone = target_block("BorealDialer")
watch = target_block("BorealDialerWatch")

checks = [
    ('platform: iOS', phone, "BorealDialer must remain an iOS target"),
    ('TARGETED_DEVICE_FAMILY: "1"', phone, "BorealDialer must remain iPhone-only"),
    ('PRODUCT_BUNDLE_IDENTIFIER: financial.boreal.dialer', phone, "iPhone bundle ID changed"),
    ('platform: watchOS', watch, "BorealDialerWatch must remain a watchOS target"),
    ('TARGETED_DEVICE_FAMILY: "4"', watch, "BorealDialerWatch must remain Watch-only"),
    ('PRODUCT_BUNDLE_IDENTIFIER: financial.boreal.dialer.watchkitapp', watch, "Watch bundle ID changed"),
    ('WKRunsIndependentlyOfCompanionApp: true', watch, "independent Watch mode was disabled"),
    ('WKCompanionAppBundleIdentifier: financial.boreal.dialer', watch, "Watch companion ID changed"),
]
for expected, block, message in checks:
    if expected not in block:
        raise SystemExit(message)

if 'TARGETED_DEVICE_FAMILY: "1,2"' in phone:
    raise SystemExit("iPad device family must not be enabled")
if "TwilioVoice" in watch:
    raise SystemExit("TwilioVoice must not be linked to BorealDialerWatch")

declared = re.findall(r"(?m)^  ([A-Za-z][A-Za-z0-9]*):\n", targets)
allowed = {"BorealDialer", "BorealDialerTests", "BorealDialerWatch", "BorealDialerWatchTests"}
unexpected = sorted(set(declared) - allowed)
if unexpected:
    raise SystemExit("Unexpected native target(s): " + ", ".join(unexpected))
PY

if rg -n --glob '*.swift' '^\s*import\s+TwilioVoice\b' Watch Sources/WatchShared; then
  echo "TwilioVoice imports are forbidden in Watch sources" >&2
  exit 1
fi

for path in Android android WearOS wearos wear-os; do
  if [[ -e "$path" ]]; then
    echo "Unsupported native platform tree found: $path" >&2
    exit 1
  fi
done

if find .github/workflows -maxdepth 1 -type f \( -iname '*android*' -o -iname '*wear*' \) -print -quit | grep -q .; then
  echo "Unsupported Android/Wear build workflow found" >&2
  exit 1
fi

echo "Supported-platform configuration verified (iPhone + Apple Watch only)."
