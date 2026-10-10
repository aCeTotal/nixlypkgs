#!/usr/bin/env bash
# Show what the download gate is doing.
set -uo pipefail

events=/run/nixly-dlgate/events
app=NixlyOS
saved_ms=15000

declare -A title=(
  [live]="Scanning during download"
  [verify]="Verifying download"
  [match]="Checking archive index"
  [unpack]="Unpacking for scan"
  [scan]="Scanning for malware"
)

saved() {
  local act
  act=$(notify-send ${1:+-r "$1"} -a "$app" -t "$saved_ms" \
    -A open="Open file location" "Scan complete" \
    "$2
No threats found. The file is ready in Downloads.")
  [ "$act" != open ] || nautilus --select "$3" >/dev/null 2>&1
}

bytes() {
  LC_ALL=C numfmt --to=iec-i --suffix=B --format=%.1f "$1"
}

# Updates the card, prints id.
progress() {
  local pct got total body=$2
  local -a bar=()
  read -r pct got total <<<"$4"
  case $3 in
    verify) ;;
    *)
      bar=(-h "int:value:$pct")
      body+=$'\n'"$(bytes "$got") of $(bytes "$total")" ;;
  esac
  notify-send -p ${1:+-r "$1"} -a "$app" -t 0 "${bar[@]}" "${title[$3]}" "$body"
}

declare -A card

tail -F -n0 "$events" 2>/dev/null | while IFS='|' read -r kind name sig file; do
  case $kind in
    scanning)
      card[$name]=$(notify-send -p ${card[$name]:+-r "${card[$name]}"} -a "$app" -t 0 "Scanning for malware" \
        "$name
The file will be available in Downloads once the scan is done.")
      continue ;;
    progress)
      card[$name]=$(progress "${card[$name]:-}" "$name" "$sig" "$file")
      continue ;;
  esac
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
