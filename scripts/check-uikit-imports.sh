#!/usr/bin/env bash
# BOREAL_DIALER_UIKIT_AND_SECTION_v13
set -euo pipefail

symbols='UIApplication|UIViewController|UIDevice|UIPasteboard|UIImage|UIScreen|UIWindow'
bad=0

while IFS= read -r file; do
  if grep -qE "\\b($symbols)\\b" "$file" && ! grep -q '^import UIKit' "$file"; then
    echo "::error file=$file::uses a UIKit symbol without 'import UIKit'"
    bad=1
  fi
done < <(find Sources UI -name '*.swift' -not -path 'Sources/BorealDialerLinux/*')

if [ "$bad" -ne 0 ]; then
  echo "SwiftUI does not re-export UIKit. Add the import or use a SwiftUI equivalent."
  exit 1
fi

echo "No UIKit symbols missing their import."
