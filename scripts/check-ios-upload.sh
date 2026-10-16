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
grep -A1 "if: always()" "$wf" | grep -q 'rm -rf "$RUNNER_TEMP/asc"' || fail "the key must be removed at the end"
python3 - "$plist" <<'PY' || fail "ExportOptions.plist must upload to App Store Connect for team 76VAY7UJKJ"
import plistlib, sys
p = plistlib.load(open(sys.argv[1], "rb"))
assert p["method"] == "app-store-connect" and p["destination"] == "upload" and p["teamID"] == "76VAY7UJKJ"
PY
echo "check-ios-upload: OK"
