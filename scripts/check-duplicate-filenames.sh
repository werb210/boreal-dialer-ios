#!/usr/bin/env bash
# BOREAL_DIALER_DUPLICATE_FILENAMES_v2
# Swift uses filenames to distinguish private declarations, so two files with the
# same basename in one module fail to compile. That error costs a full macOS
# runner to surface; this catches it on ubuntu in seconds.
set -euo pipefail

dupes="$(find Sources UI -name '*.swift' -not -path 'Sources/BorealDialerLinux/*' \
  | xargs -n1 basename | sort | uniq -d)"

if [ -n "$dupes" ]; then
  echo "::error::Duplicate Swift filenames in the BorealDialer target:"
  while IFS= read -r name; do
    echo "  $name"
    find Sources UI -name "$name" -not -path 'Sources/BorealDialerLinux/*' | sed 's/^/      /'
  done <<< "$dupes"
  echo "Rename one of each pair after the type it declares."
  exit 1
fi

echo "No duplicate Swift filenames."
