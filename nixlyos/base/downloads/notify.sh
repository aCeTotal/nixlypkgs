#!/usr/bin/env bash
# Show what the download gate is doing.
set -uo pipefail

events=/run/nixly-dlgate/events
app=NixlyOS
saved_ms=15000

saved() {
  local act
  act=$(notify-send ${1:+-r "$1"} -a "$app" -t "$saved_ms" \
    -A open="Open file location" "Scan complete" \
    "$2
No threats found. The file is ready in Downloads.")
  [ "$act" != open ] || nautilus --select "$3" >/dev/null 2>&1
}

declare -A card

tail -F -n0 "$events" 2>/dev/null | while IFS='|' read -r kind name sig file; do
  if [ "$kind" = scanning ]; then
    card[$name]=$(notify-send -p -a "$app" -t 0 "Scanning for malware" \
      "$name
The file will be available in Downloads once the scan is done.")
    continue
  fi
  id=${card[$name]:-}
  unset 'card[$name]'
  case $kind in
    clean)
      saved "$id" "$name" "$file" & ;;
    threat)
      notify-send ${id:+-r "$id"} -u critical -a "$app" -t 0 "Download blocked" \
        "$name
$sig — removed" ;;
    held)
      notify-send ${id:+-r "$id"} -u critical -a "$app" -t 0 "Download held" \
        "$name
$sig — cannot be verified, so it stays locked away

Open it in a sandbox:
nixly-open-held $file" ;;
  esac
done
