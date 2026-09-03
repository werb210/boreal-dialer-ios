#!/usr/bin/env bash
set -euo pipefail

watch_sources="Watch"

if rg -n --glob '*.swift' 'try!\s*WatchAPIClient|await\s+auth\.session!' "$watch_sources"; then
  echo "Watch authentication code contains a prohibited crash path." >&2
  exit 1
fi

echo "Watch authentication crash-path guard passed."
