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
call_directory = target_block("BorealDialerCallDirectory")
watch_widget = target_block("BorealWatchWidget")

checks = [
    ('platform: iOS', phone, "BorealDialer must remain an iOS target"),
    ('TARGETED_DEVICE_FAMILY: "1"', phone, "BorealDialer must remain iPhone-only"),
    ('PRODUCT_BUNDLE_IDENTIFIER: com.borealfinancial.dialer', phone, "iPhone bundle ID changed"),
    ('platform: watchOS', watch, "BorealDialerWatch must remain a watchOS target"),
    ('TARGETED_DEVICE_FAMILY: "4"', watch, "BorealDialerWatch must remain Watch-only"),
    ('PRODUCT_BUNDLE_IDENTIFIER: com.borealfinancial.dialer.watchkitapp', watch, "Watch bundle ID changed"),
    ('WKRunsIndependentlyOfCompanionApp: true', watch, "independent Watch mode was disabled"),
    ('WKCompanionAppBundleIdentifier: com.borealfinancial.dialer', watch, "Watch companion ID changed"),
    ('platform: iOS', call_directory, "Call Directory must remain an iOS target"),
    ('PRODUCT_BUNDLE_IDENTIFIER: com.borealfinancial.dialer.calldirectory', call_directory, "Call Directory bundle ID changed"),
    ('NSExtensionPointIdentifier: com.apple.callkit.call-directory', call_directory, "Call Directory extension point changed"),
    ('platform: watchOS', watch_widget, "Watch widget must remain a watchOS target"),
    ('TARGETED_DEVICE_FAMILY: "4"', watch_widget, "Watch widget must remain Watch-only"),
    ('PRODUCT_BUNDLE_IDENTIFIER: com.borealfinancial.dialer.watchkitapp.widget', watch_widget, "Watch widget bundle ID changed"),
    ('NSExtensionPointIdentifier: com.apple.widgetkit-extension', watch_widget, "Watch widget extension point changed"),
]
for expected, block, message in checks:
    if expected not in block:
        raise SystemExit(message)

if 'TARGETED_DEVICE_FAMILY: "1,2"' in phone:
    raise SystemExit("iPad device family must not be enabled")
if "TwilioVoice" in watch:
    raise SystemExit("TwilioVoice must not be linked to BorealDialerWatch")

declared = re.findall(r"(?m)^  ([A-Za-z][A-Za-z0-9]*):\n", targets)
allowed = {
    "BorealDialer",
    "BorealDialerTests",
    "BorealDialerWatch",
    "BorealDialerWatchTests",
    "BorealWatchWidget",
    "BorealDialerLiveActivity",
    "BorealDialerCallDirectory",
    "BorealDialerNotificationService",  # BOREAL_DIALER_v822_CARPLAY - texts read aloud by Siri in CarPlay
    "BorealDialerIntents",  # BOREAL_DIALER_CARPLAY_INTENTS - required for iOS to list the app in CarPlay
}
unexpected = sorted(set(declared) - allowed)
if unexpected:
    raise SystemExit("Unexpected native target(s): " + ", ".join(unexpected))
PY

if rg -n --glob '*.swift' '^\s*import\s+TwilioVoice\b' Watch Sources/WatchShared; then
  echo "TwilioVoice imports are forbidden in Watch sources" >&2
  exit 1
fi

# BOREAL_ANDROID_DIALER_v1 - android/ is the Android dialler (its own Gradle project, built by
# .github/workflows/android.yml). It must stay that one native Gradle app: no Wear OS tree and no other Android tree.
for path in Android WearOS wearos wear-os; do
  if [[ -e "$path" ]]; then
    echo "Unsupported native platform tree found: $path" >&2
    exit 1
  fi
done
if [[ -e android ]]; then
  [[ -f android/settings.gradle && -f android/app/build.gradle ]] || { echo "android/ must be the Android dialler's Gradle project" >&2; exit 1; }
  if [[ -e android/wear ]] || grep -q "include ':wear'" android/settings.gradle; then
    echo "Wear OS is not supported" >&2
    exit 1
  fi
fi

if find .github/workflows -maxdepth 1 -type f \( -iname '*android*' -o -iname '*wear*' \) ! -name 'android.yml' -print -quit | grep -q .; then
  echo "Unsupported Android/Wear build workflow found (the Android dialler is built by android.yml only)" >&2
  exit 1
fi

echo "Supported-platform configuration verified (iPhone + Apple Watch, and the Android dialler in android/)."
