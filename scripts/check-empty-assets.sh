#!/usr/bin/env bash
# BOREAL_DIALER_APPICON_PLACEHOLDER_v25
# A zero-byte image in an asset catalogue fails asset compilation with a message
# that names the catalogue, not the file. Catch it before the macOS runner does.
set -euo pipefail

bad=0
while IFS= read -r file; do
  if [ ! -s "$file" ]; then
    echo "::error file=$file::zero-byte asset"
    bad=1
  fi
done < <(find Assets.xcassets Assets -type f \( -name '*.png' -o -name '*.jpg' -o -name '*.pdf' \) 2>/dev/null)

if [ "$bad" -ne 0 ]; then
  echo "Zero-byte assets break asset catalogue compilation."
  exit 1
fi

echo "No empty assets."
