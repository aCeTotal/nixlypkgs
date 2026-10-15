#!/usr/bin/env bash
# Scan each new file in Downloads once, out of reach.
set -uo pipefail

dir=$1
stage=/home/.nixly-dlscan
q=/var/lib/nixly-quarantine
events=/run/nixly-dlgate/events
mark=trusted.nixly.scanned

event() {
  printf '%s|%s|%s|%s\n' "$1" "$2" "$3" "${4:-}" >>"$events"
}

hold() {
  local dst=$q/$2
  [ ! -e "$dst" ] || dst=$q/$2.$RANDOM
  mv -f -- "$1" "$dst"
  event held "$2" "$3" "$(basename -- "$dst")"
}

check() {
  local f=$1 name s reason rc=0
  [ -f "$f" ] && [ ! -L "$f" ] || return 0
  getfattr -n "$mark" -- "$f" >/dev/null 2>&1 && return 0
  name=$(basename -- "$f")
  s=$(mktemp -u "$stage/XXXXXXXX")
  mv -T -- "$f" "$s" 2>/dev/null || return 0

  reason=$(nixly-scan-file "$s") || rc=$?
  case $rc in
    0)
      setfattr -n "$mark" -v 1 -- "$s" 2>/dev/null || true
      # Same-name arrival becomes a backup.
      mv -T --backup=numbered -- "$s" "$f" ;;
    1) rm -f -- "$s"; event threat "$name" "$reason" ;;
    *) hold "$s" "$name" "$reason" ;;
  esac
}

inotifywait -q -m -e close_write,moved_to --format '%w%f' "$dir" 2>/dev/null \
| while IFS= read -r f; do
  # A download in flight is not a file yet.
  case $f in
    *.part|*.crdownload|*.download|*.tmp|*.partial) continue ;;
  esac
  check "$f"
done
