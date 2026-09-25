#!/bin/bash
# BOREAL_DIALER_v532 - every WidgetKit StaticConfiguration must declare a
# container background, or iOS 17 / watchOS 10 shows "Please adopt
# containerBackground API" instead of the widget.
set -euo pipefail
fail=0
for f in $(grep -rl "StaticConfiguration(" --include=*.swift LiveActivity WatchWidget); do
  if ! grep -q "containerBackground(" "$f" && ! grep -q "WidgetBackground()" "$f"; then
    echo "missing containerBackground: $f"; fail=1
  fi
done
grep -q ".dialerWidgetBackground()" LiveActivity/BorealDialerWidget.swift || { echo "iPhone widget not using dialerWidgetBackground"; fail=1; }
[ "$fail" -eq 0 ] && echo "OK: every widget declares a container background"
exit "$fail"
