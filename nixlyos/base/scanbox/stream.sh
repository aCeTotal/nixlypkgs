#!/usr/bin/env bash
# Scan archives while they download.
set -uo pipefail
enable -f stat stat
enable -f sleep sleep

f=$1
# Caller writes the finished path here.
mark=$2
clean=0
found=1
unverifiable=2
no_verdict=3
box=/var/lib/nixly-scanbox
limit=$(( 2 * 1024 * 1024 * 1024 ))
poll_s=1
tail_s=0.2

exec {keep}<"$f" || exit "$no_verdict"
held=/proc/$$/fd/$keep

kind=""
final=""
unverified=0
shown=0
reader=""

work=$(mktemp -d "$box/XXXXXXXX") || exit "$no_verdict"
trap 'rm -rf "$work"' EXIT INT TERM HUP
mkdir "$work/x" "$work/lists"
: >"$work/seen"

# First threat ends the scan.
record() {
  printf '%s — %s\n' "${1##*/}" "$2"
  exit "$found"
}

# Tail's fdinfo for the download.
reader_pos() {
  local pid fd
  read -r pid 2>/dev/null <"$work/reader" || return 1
  for fd in /proc/"$pid"/fd/*; do
    [ "$fd" -ef "$held" ] || continue
    printf '%s' "/proc/$pid/fdinfo/${fd##*/}"
    return 0
  done
  return 1
}

# Archive bytes read, once a second.
live() {
  local pos=0
  local -A st
  [ "$EPOCHSECONDS" != "$shown" ] || return 0
  shown=$EPOCHSECONDS
  [ -n "$reader" ] || reader=$(reader_pos) || reader=""
  stat -A st "$held" || return 0
  # Tail gone means all read.
  [ -z "$reader" ] || read -r _ pos 2>/dev/null <"$reader" || pos=${st[size]}
  printf 'live %s %s %s\n' "$(( pos * 100 / st[size] ))" "$pos" "${st[size]}" >&3
}

# Past the limit, still downloading.
grown() {
  local -A st
  while [ -e "$f" ]; do
    stat -A st "$held" || return 1
    [ "${st[size]}" -le "$limit" ] || return 0
    sleep "$poll_s"
  done
  return 1
}

hex() {
  od -An -tx1 -j "$1" -N "$2" -- "$held" | tr -d ' \n'
}

# Front-to-back formats only.
sniff() {
  case $(hex 0 4):$(hex 257 5) in
    504b0304:*) kind=zip ;;
    1f8b*|fd377a58:*|28b52ffd:*|425a68*|*:7573746172) kind=tar ;;
    *) return 1 ;;
  esac
}

unpack() {
  local sentinel
  ( while [ -e "$f" ]; do sleep "$tail_s"; done ) &
  sentinel=$!
  mkfifo "$work/in"
  tail -s "$tail_s" -c +1 -f --pid="$sentinel" -- "$held" >"$work/in" {keep}<&- &
  echo "$!" >"$work/reader"
  tee >(b3sum --no-names >"$work/sum") <"$work/in" |
    bsdtar -xvf - -C "$work/x" 2>&1
}

# Lines end once members land.
feed() {
  local line p
  local -A st
  while IFS= read -r line; do
    [ "${line:0:2}" = "x " ] || continue
    p=$work/x/${line:2}
    stat -L -A st "$p" 2>/dev/null && [ "${st[type]}" = - ] || continue
    if [ "${st[size]}" -le "$limit" ]; then
      printf '%s\t%s\0' "${st[size]}" "$p"
      continue
    fi
    # Central directory pass covers these.
    [ "$kind" != zip ] || rm -f -- "$p"
  done
}

# Fingerprint for zip, then drop.
retire() {
  local -a files
  mapfile -t files <"$1"
  [ "$kind" != zip ] || b3sum --no-names -- "${files[@]}" >>"$work/seen"
  rm -f -- "${files[@]}"
}

verdict_line() {
  local s rc list
  case $1 in
    "batch "*)
      read -r _ _ rc list <<<"$1"
      [ "$rc" != 2 ] || unverified=1
      retire "$list"
      live ;;
    *" FOUND")
      s=${1##*: }
      s=${s% FOUND}
      case $s in *Limits.Exceeded*) ;; *) record "${1%: *}" "$s" ;; esac ;;
  esac
}

scan_live() {
  local line
  while IFS= read -r line; do
    verdict_line "$line"
  done < <(exec 3>&-; { unpack || : 2>/dev/null >"$work/failed"; } | feed |
    nixly-scan-batches "$work/lists")
}

# Gives up if download deleted.
finished() {
  local -A st
  until [ -s "$mark" ]; do
    stat -A st "$held" && [ "${st[nlink]}" -gt 0 ] || return 1
    sleep "$tail_s"
  done
  final=$(<"$mark")
}

# Leftover and oversized tar members.
scan_rest() {
  local line p
  while IFS= read -r line; do
    verdict_line "$line"
  done < <(find "$work/x" -type f -size -"$(( limit + 1 ))"c -printf '%s\t%p\0' |
    nixly-scan-batches "$work/lists" 3>&-)
  while IFS= read -r -d '' p; do
    deep "$p" 1 3>&-
  done < <(find "$work/x" -type f -size +"$limit"c -print0)
}

# Expand prints its own findings.
deep() {
  local rc=0
  nixly-scan-expand "$@" || rc=$?
  case $rc in
    "$clean") ;;
    "$found") exit "$found" ;;
    *) unverified=1 ;;
  esac
}

grown && sniff || exit "$no_verdict"
live
scan_live
finished || exit "$no_verdict"
[ ! -e "$work/failed" ] && [ "$unverified" = 0 ] || exit "$no_verdict"
printf 'verify 0 0 0\n' >&3
[ "$(b3sum --no-names -- "$final")" = "$(<"$work/sum")" ] || exit "$no_verdict"

case $kind in
  # Central directory may differ.
  zip) deep "$final" 0 "$work/seen" ;;
  tar) scan_rest ;;
esac

[ "$unverified" = 0 ] || exit "$unverifiable"
exit "$clean"
