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

# BOREAL_DIALER_SERVER_PATHS_v789 - BF-Server routes live under /api/ with no
# version segment. APIConfig.BASE_URL already ends in /api, so a path literal
# must not repeat /api/ or add /v1/.
# bi-server is a separate deployment whose routes are /v1/bi/...; only BF-Server
# paths are checked.
if grep -rnE '"/(api/)?v1/' Sources UI --include='*.swift' | grep -v '"/v1/bi/'; then
  echo "::error::BF-Server paths have no /v1/ segment"
  exit 1
fi
if grep -rnE '"/api/' Sources UI --include='*.swift'; then
  echo "::error::path literals are relative to APIConfig.BASE_URL, which already ends in /api"
  exit 1
fi

# BOREAL_DIALER_SERVER_PATHS_v789 - the team chat, SMS typing, Maya and
# notification endpoints added in v789 must stay wired. Each entry is
# "file|literal fragment that builds the path".
missing=0
while IFS='|' read -r file fragment; do
  [ -z "$file" ] && continue
  if ! grep -qF -- "$fragment" "$file"; then
    echo "::error file=$file::missing server path fragment: $fragment"
    missing=1
  fi
done <<'PATHS'
UI/Team/TeamParity.swift|"/team/channels/\(pathSegment(channelId))/messages/\(pathSegment(messageId))"
UI/Team/TeamParity.swift|method: "PATCH", json: ["body": trimmed]
UI/Team/TeamParity.swift|messageId: messageId), method: "DELETE")
UI/Team/TeamParity.swift|+ "/reactions",
UI/Team/TeamParity.swift|+ "/reactions?emoji=" + Self.queryValue(emoji), method: "DELETE")
UI/Team/TeamParity.swift|+ "/pin", method: "POST")
UI/Team/TeamParity.swift|+ "/pins")
UI/Team/TeamParity.swift|+ "/typing", method: "POST")
UI/Team/TeamParity.swift|+ "/search?q=" + Self.queryValue(trimmed))
UI/Team/TeamParity.swift|+ "/reads")
UI/SMS/SMSTyping.swift|makeRequest(path: "/communications/messages/typing",
UI/SMS/SMSTyping.swift|["contactId": contactId, "side": "staff"]
UI/SMS/SMSTyping.swift|"/communications/messages/typing?contactId=\(id)&side=client"
UI/Messages/MayaSessionsView.swift|"/communications/maya-sessions"
UI/Messages/MayaSessionsView.swift|"/communications/maya-sessions/\(TeamParityStore.pathSegment(sessionId))/messages"
UI/Notifications/NotificationsView.swift|"/notifications/\(Self.pathSegment(id))/read", method: "POST"
UI/Notifications/NotificationsView.swift|"/notifications/read-all", method: "POST"
Sources/Notifications/AlertPushRouting.swift|path: "/staff/push-token", method: "POST"
Sources/Notifications/AlertPushRouting.swift|path: "/staff/push-token", method: "DELETE"
Sources/Voice/AfterCallSummary.swift|"/calls/\($0)/summary"
Sources/Voice/CallerCard.swift|"/voice/caller-card?phone=\(encoded)"
Sources/WatchShared/QuickReplies.swift|"/templates/quick?channel=\(channel)"
Watch/WatchQuickReplies.swift|path: "/templates/quick", query: [URLQueryItem(name: "channel", value: "sms")]
Sources/DeepLink/StaffBriefingIntents.swift|nextFollowUpPath = "/staff/next-follow-up"
Sources/DeepLink/StaffBriefingIntents.swift|missedSummaryPath = "/staff/missed-summary"
Sources/Services/CallHours.swift|static let path = "/staff/call-hours"
Sources/Services/CallHours.swift|makeRequest(path: path, method: "PUT"
PATHS
if [ "$missing" -ne 0 ]; then
  exit 1
fi
echo "v789 endpoints wired: team edit/delete/reactions/pin/pins/typing/search/reads, SMS typing, Maya sessions, notification read."
echo "v821 endpoints wired: call summary, caller card, quick replies (iPhone + Watch), next follow-up, missed summary, call hours."

echo "No known-dead paths."
