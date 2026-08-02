#!/usr/bin/env bash
# BOREAL_DIALER_CATCH_SHADOWING_v19
set -euo pipefail

bad=0
while IFS= read -r file; do
  if awk '
    /catch[[:space:]]*\{/ { depth = 1; next }
    depth > 0 {
      if ($0 ~ /^[[:space:]]*error[[:space:]]*=[[:space:]]*"/) {
        printf "::error file=%s,line=%d::assigns to the catch binding `error`; use self.error\n", FILENAME, FNR
        found = 1
      }
      if ($0 ~ /^[[:space:]]*\}[[:space:]]*$/) depth = 0
    }
    END { exit found ? 1 : 0 }
  ' "$file"; then
    :
  else
    bad=1
  fi
done < <(find Sources UI -name '*.swift' -not -path 'Sources/BorealDialerLinux/*')

if [ "$bad" -ne 0 ]; then
  echo "Inside catch, `error` is the caught value and shadows any property of the same name."
  exit 1
fi

echo "No shadowed error assignments."
