#!/usr/bin/env bash
# Only confirmed, clean downloads leave Brave.
set -uo pipefail

inbox=$1
dest=$2
stage=$3
verdicts=$stage/verdicts
q=/var/lib/nixly-quarantine
events=/run/nixly-dlgate/events
limit=$(( 2 * 1024 * 1024 * 1024 ))
action=org.nixlyos.download-save
user=$(stat -c %U -- "$inbox")
uid=$(stat -c %u -- "$inbox")

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

# Polkit asks the user's session.
subject() {
  local pid stat fields
  pid=$(pgrep -o -u "$user" -x nixlyOS) || return 1
  read -r stat <"/proc/$pid/stat" || return 1
  read -ra fields <<<"${stat##*) }"
  printf '%s,%s,%s' "$pid" "${fields[19]}" "$uid"
}

markup() {
  local s=${1//&/&amp;}
  s=${s//</&lt;}
  printf '%s' "${s//>/&gt;}"
}

# 0 yes, 2 no agent, 1 and 3 refused.
confirm() {
  pkcheck --action-id "$action" --process "$1" --allow-user-interaction \
    --detail file "$(markup "$2")" >/dev/null 2>&1
}

# Inode plus birth time survives the rename, never reuse.
key() {
  stat -c %i.%W -- "$1" 2>/dev/null
}

claim() {
  (set -o noclobber; : >"$verdicts/$1") 2>/dev/null
}

ask() {
  local who rc=2
  if who=$(subject); then
    confirm "$who" "$2" && rc=0 || rc=$?
  fi
  echo "$rc" >"$verdicts/$1"
  return "$rc"
}

verdict() {
  local v=$verdicts/$1 rc
  if claim "$1"; then
    ask "$1" "$2" || true
  fi
  while [ -e "$v" ] && [ ! -s "$v" ]; do
    inotifywait -qq -t 1 -e close_write -- "$v" 2>/dev/null || true
  done
  rc=$(cat -- "$v" 2>/dev/null) || rc=1
  rm -f -- "$v"
  return "$rc"
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
  local f=$1 name s reason rc id
  name=$(basename -- "$f")
  id=$(key "$f") || return 0
  # Waits in the inbox for a session.
  [ -e "$verdicts/$id" ] || subject >/dev/null || return 0
  s=$(mktemp -u "$stage/XXXXXXXX")
  # Out of Brave's reach first.
  mv -T -- "$f" "$s" 2>/dev/null || return 0
  if [ -L "$s" ] || [ ! -f "$s" ]; then
    rm -rf -- "$s"
    return 0
  fi

  if verdict "$id" "$name"; then rc=0; else rc=$?; fi
  case $rc in
    0) ;;
    2) hold "$s" "$name" "not confirmed"; return 0 ;;
    *) rm -f -- "$s"; return 0 ;;
  esac

  event scanning "$name" ""
  if reason=$(scan "$s"); then rc=0; else rc=$?; fi
  case $rc in
    0) release "$s" "$name" ;;
    1) rm -f -- "$s"; event threat "$name" "$reason" ;;
    *) hold "$s" "$name" "$reason" ;;
  esac
}

# A refusal aborts the download in Brave.
start() {
  local rc=0
  ask "$2" "$(basename -- "${1%.crdownload}")" || rc=$?
  case $rc in 1|3) rm -f -- "$1" ;; esac
}

# Prompts as soon as Brave starts writing.
watch_starts() {
  local f id
  inotifywait -q -m -e create --format %f "$inbox" 2>/dev/null \
  | while IFS= read -r f; do
    case $f in *.crdownload) ;; *) continue ;; esac
    id=$(key "$inbox/$f") || continue
    claim "$id" && start "$inbox/$f" "$id" &
  done
}

finished() {
  case $1 in
    *.part|*.crdownload|*.download|*.tmp|*.partial) return 1 ;;
  esac
}

rm -rf -- "$verdicts"
mkdir -m 0700 -- "$verdicts"
watch_starts &

for f in "$inbox"/*; do
  finished "$f" && process "$f"
done
inotifywait -q -m -e close_write,moved_to --format '%f' "$inbox" 2>/dev/null \
| while IFS= read -r f; do
  finished "$f" && process "$inbox/$f"
done
