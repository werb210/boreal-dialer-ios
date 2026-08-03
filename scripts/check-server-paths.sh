#!/usr/bin/env bash
# BOREAL_DIALER_LAST_DEAD_ROUTES_v43
# Six dead endpoints reached production in this app - /voice/calls/answer,
# /voice/calls/end, /voice/calls/active, /voice/calls/log, /voice/device-token,
# /voice/presence - plus /crm/events and a marketing-blast route that a
# one-to-one SMS was pointed at. Every one of them failed silently behind a
# try?, so nothing surfaced until someone used the feature.
#
# This does not prove a path exists; it lists every path the app calls so the
# set is reviewable in one place rather than scattered across 40 files.
set -euo pipefail

echo "Server paths this app calls:"
grep -rhoE '"(/[a-zA-Z0-9/_.-]+)' Sources UI --include='*.swift' \
  | tr -d '"' \
  | grep -v '^/dev/null$' \
  | sort -u \
  | sed 's/^/  /'

if grep -rqE '"/voice/(calls/(answer|end|active|log)|device-token|presence)' Sources UI --include='*.swift'; then
  echo "::error::a known-dead /voice route is back"
  exit 1
fi
if grep -rq '"/crm/events' Sources UI --include='*.swift'; then
  echo "::error::/crm/events does not exist; use /calendar/events"
  exit 1
fi
if grep -rq '"/sms/send' Sources UI --include='*.swift'; then
  echo "::error::/sms/send is the MARKETING BLAST route; use /communications/sms"
  exit 1
fi

# BOREAL_DIALER_RESOLVE_CALLER_CONTRACT_v45
if grep -rq '"/voice/resolve-caller?' Sources UI --include='*.swift'; then
  echo "::error::/voice/resolve-caller is a POST that reads the phone from the body, not a query string"
  exit 1
fi

echo "No known-dead paths."
