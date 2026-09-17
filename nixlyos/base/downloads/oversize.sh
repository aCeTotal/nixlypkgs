#!/usr/bin/env bash
# Files past the engine ceiling are quarantined, then unpacked and scanned
# from the inside. Clean ones go back where they came from, silently.
set -uo pipefail

q=/var/lib/nixly-quarantine
events=/run/nixly-dlgate/events
limit=$(( 2 * 1024 * 1024 * 1024 ))

inotifywait -q -m -e close_write,moved_to --format '%w%f' "$@" 2>/dev/null \
| while IFS= read -r f; do
  [ -f "$f" ] || continue
  # A download in flight is not a file yet.
  case $f in
    *.part|*.crdownload|*.download|*.tmp|*.partial) continue ;;
  esac
  size=$(stat -c %s -- "$f" 2>/dev/null) || continue
  [ "$size" -gt "$limit" ] || continue

  name=$(basename -- "$f")
  dst=$q/$name
  [ ! -e "$dst" ] || dst=$q/$name.$RANDOM
  mv -f -- "$f" "$dst" 2>/dev/null || continue

  systemctl start --no-block clamav-daemon.service 2>/dev/null || true
  if found=$(nixly-scan-expand "$dst"); then
    rc=0
  else
    rc=$?
  fi
  case $rc in
    0)
      mv -f -- "$dst" "$f" 2>/dev/null || true ;;
    1)
      rm -f -- "$dst"
      printf 'threat|%s|%s|\n' "$name" "$(head -1 <<<"$found")" >>"$events" ;;
    *)
      printf 'held|%s|too large to scan and could not be unpacked|%s\n' \
        "$name" "$(basename -- "$dst")" >>"$events" ;;
  esac
done
