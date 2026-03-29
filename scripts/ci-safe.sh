#!/bin/bash

if [[ "$RUNNER_OS" != "macOS" ]]; then
  echo "Skipping iOS build — requires macOS + Xcode"
  exit 0
fi

set -e

cd ios

pod install --repo-update

xcodebuild \
  -workspace BorealDialer.xcworkspace \
  -scheme BorealDialer \
  -sdk iphonesimulator \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  clean build
