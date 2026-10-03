#!/usr/bin/env bash
# Only clean downloads leave Brave.
set -uo pipefail

inbox=$1
dest=$2
stage=$3
q=/var/lib/nixly-quarantine
events=/run/nixly-dlgate/events
limit=$(( 2 * 1024 * 1024 * 1024 ))

shopt -s nullglob dotglob

event() {
  printf '%s|%s|%s|%s\n' "$1" "$2" "$3" "${4:-}" >>"$events"
}

unique() {
  local name=$1 stem=$1 ext="" n=1
  case $name in ?*.*) stem=${name%.*} ext=.${name##*.} ;; esac
  while [ -e "$dest/$name" ]; do
    name="$stem ($n)$ext"
    n=$(( n + 1 ))
  done
  printf '%s' "$name"
}

# 0 clean, 1 threat, 2 unverifiable.
scan() {
  local s=$1 out rc
  if [ "$(stat -c %s -- "$s")" -gt "$limit" ]; then
    if out=$(nixly-scan-expand "$s"); then rc=0; else rc=$?; fi
    printf '%s' "${out:-too large to scan and could not be unpacked}" | head -1
    return "$rc"
  fi
  if out=$(clamdscan --fdpass --no-summary --infected --wait --ping 120:1 -- "$s" 2>/dev/null); then
    rc=0
  else
    rc=$?
  fi
  out=${out##*: }
  out=${out% FOUND}
  case $rc:$out in
    0:*) return 0 ;;
    1:*ncrypted*|1:*Limits.Exceeded*) rc=2 ;;
    1:*) ;;
    *) out="could not be scanned" rc=2 ;;
  esac
  printf '%s' "$out"
  return "$rc"
}

hold() {
  local s=$1 name=$2 reason=$3 dst=$q/$2
  [ ! -e "$dst" ] || dst=$q/$name.$RANDOM
  mv -f -- "$s" "$dst"
  event held "$name" "$reason" "$(basename -- "$dst")"
}

release() {
  local s=$1 name=$2 out
  out=$dest/$(unique "$name")
  mv -- "$s" "$out"
  event clean "$name" "" "$out"
}

process() {
  local f=$1 name s reason rc
  name=$(basename -- "$f")
  s=$(mktemp -u "$stage/XXXXXXXX")
  # Out of Brave's reach first.
  mv -T -- "$f" "$s" 2>/dev/null || return 0
  if [ -L "$s" ] || [ ! -f "$s" ]; then
    rm -rf -- "$s"
    return 0
  fi

  systemctl start --no-block clamav-daemon.service 2>/dev/null || true
  if reason=$(scan "$s"); then rc=0; else rc=$?; fi
  case $rc in
    0) release "$s" "$name" ;;
    1) rm -f -- "$s"; event threat "$name" "$reason" ;;
    *) hold "$s" "$name" "$reason" ;;
  esac
}

sweep() {
  local f
  for f in "$inbox"/*; do
    case $f in
      *.part|*.crdownload|*.download|*.tmp|*.partial) continue ;;
    esac
    process "$f"
  done
}

sweep
inotifywait -q -m -e close_write,moved_to --format . "$inbox" 2>/dev/null \
| while read -r _; do
  sweep
done
