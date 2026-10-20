#!/usr/bin/env bash
# BOREAL_DIALER_v815_IOS_UPLOAD - the cloud upload workflow stays manual-only, uses the released Xcode and the
# company team, reads the key only from secrets, deletes it afterwards, and numbers every target the same.
set -euo pipefail
wf=.github/workflows/ios-upload.yml
plist=Config/ci/ExportOptions.plist
fail() { echo "check-ios-upload: $1" >&2; exit 1; }
on_block="$(awk '/^on:/{f=1} /^concurrency:/{f=0} f' "$wf")"
grep -q "workflow_dispatch:" <<<"$on_block" || fail "must be started by hand (workflow_dispatch)"
if grep -Eq "^\s+(push|pull_request|schedule):" <<<"$on_block"; then fail "must not run on push, pull request or a schedule"; fi
grep -q "xcode-version: latest-stable" "$wf" || fail "must use the released Xcode"
grep -q "DEVELOPMENT_TEAM=76VAY7UJKJ" "$wf" || fail "must sign with the company team"
for s in ASC_KEY_ID ASC_ISSUER_ID ASC_KEY_P8; do grep -q "secrets.$s" "$wf" || fail "missing secret $s"; done
if grep -q "BEGIN PRIVATE KEY" "$wf"; then fail "a private key is written into the workflow"; fi
grep -q 'CURRENT_PROJECT_VERSION="$BUILD_NUMBER"' "$wf" || fail "every target must get the run's build number"
grep -A1 "if: always()" "$wf" | grep 'rm -rf "$RUNNER_TEMP/asc"' >/dev/null || fail "the key must be removed at the end"
# BOREAL_v833_CERT_CLEANUP - leftover cloud development certificates are deleted before each archive, never failing the run.
grep -B2 "node scripts/asc-cleanup-dev-certs.mjs" "$wf" | grep "continue-on-error: true" >/dev/null || fail "certificate cleanup must run (and never fail the run)"
awk '/asc-cleanup-dev-certs/{c=NR} /xcodebuild archive/{a=NR} END{exit !(c && a && c < a)}' "$wf" || fail "certificate cleanup must run before the archive"
grep -q 'DEV_TYPES = new Set(\["DEVELOPMENT", "IOS_DEVELOPMENT"\])' scripts/asc-cleanup-dev-certs.mjs || fail "certificate cleanup may only touch development certificates"
python3 - "$plist" <<'PY' || fail "ExportOptions.plist must upload to App Store Connect for team 76VAY7UJKJ"
import plistlib, sys
p = plistlib.load(open(sys.argv[1], "rb"))
assert p["method"] == "app-store-connect" and p["destination"] == "upload" and p["teamID"] == "76VAY7UJKJ"
PY
# BOREAL_DIALER_v816_WATCH_ICON - App Store Connect refuses a Watch app without an icon.
# BOREAL_DIALER_v817_CHECK_FLAKE - grep (not grep -q) so awk never gets SIGPIPE under pipefail, which failed this check at random.
[ -s Watch/Assets.xcassets/AppIcon.appiconset/WatchIcon-1024.png ] || fail "the Watch app needs Watch/Assets.xcassets/AppIcon"
grep -q '"platform" : "watchos"' Watch/Assets.xcassets/AppIcon.appiconset/Contents.json || fail "the Watch icon must be a watchOS icon"
awk '/^  BorealDialerWatch:$/{n++} n==2' project.yml | grep "ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon" >/dev/null || fail "the Watch target must name its app icon"
awk '/^  BorealDialerWatch:$/{n++} n==2' project.yml | grep "CFBundleIconName: AppIcon" >/dev/null || fail "the Watch Info.plist must name its app icon"
echo "check-ios-upload: OK"
