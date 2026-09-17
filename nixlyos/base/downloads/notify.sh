#!/usr/bin/env bash
# Show what the download gate stopped.
set -uo pipefail

events=/run/nixly-dlgate/events

tail -F -n0 "$events" 2>/dev/null | while IFS='|' read -r kind name sig file; do
  case $kind in
    threat)
      notify-send -u critical -a NixlyOS -t 0 "Download blocked" \
        "$name
$sig — removed" ;;
    held)
      notify-send -u critical -a NixlyOS -t 0 "Download held" \
        "$name
$sig — cannot be verified, so it stays locked away

Open it in a sandbox:
nixly-open-held $file" ;;
  esac
done
