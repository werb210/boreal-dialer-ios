#!/usr/bin/env bash
# BOREAL_DIALER_WATCH_FACE_v371 - the Watch app writes and the widget reads the
# same app-group keys, and every complication link has a route. Either side
# changing alone silently blanks the watch face again.
set -euo pipefail
for key in presence.status calls.missed tasks.due; do
  grep -q "\"$key\"" Watch/WatchFaceSync.swift || { echo "::error::WatchFaceSync does not write $key"; exit 1; }
  grep -q "\"$key\"" WatchWidget/BorealWatchWidget.swift || { echo "::error::widget does not read $key"; exit 1; }
done
for target in $(grep -oE 'borealwatch://[a-z]+' WatchWidget/BorealWatchWidget.swift | sed 's#borealwatch://##' | sort -u); do
  grep -q "\"$target\"" Watch/WatchFaceSync.swift || { echo "::error::complication link $target has no route"; exit 1; }
  grep -q "complicationBinding(\"$target\")" Watch/WatchRootView.swift || { echo "::error::no screen for $target"; exit 1; }
done
grep -q '"/watch/face"' Watch/WatchFaceSync.swift || { echo "::error::face fetch path changed"; exit 1; }
grep -q "containerBackground(for: .widget)" WatchWidget/BorealWatchWidget.swift || { echo "::error::widgets need containerBackground on watchOS 10"; exit 1; }
echo "OK: watch face keys, links and backgrounds line up"
