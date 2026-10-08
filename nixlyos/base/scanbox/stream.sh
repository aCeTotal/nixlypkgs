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
nfound=0
unverified=0
scanned=0
shown=0

work=$(mktemp -d "$box/XXXXXXXX") || exit "$no_verdict"
trap 'rm -rf "$work"' EXIT INT TERM HUP
mkdir "$work/x" "$work/lists"
: >"$work/seen"

record() {
  printf '%s — %s\n' "${1##*/}" "$2"
  nfound=$(( nfound + 1 ))
}

# Bytes only, once a second.
live() {
  [ "$EPOCHSECONDS" != "$shown" ] || return 0
  shown=$EPOCHSECONDS
  printf 'live 0 %s 0\n' "$scanned" >&3
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
  tail -s "$tail_s" -c +1 -f --pid="$sentinel" -- "$held" |
    tee >(b3sum --no-names >"$work/sum") |
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
  local s bytes rc list
  case $1 in
    "batch "*)
      read -r _ bytes rc list <<<"$1"
      [ "$rc" != 2 ] || unverified=1
      retire "$list"
      scanned=$(( scanned + bytes ))
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
  done < <({ unpack || : >"$work/failed"; } | feed |
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
    nixly-scan-batches "$work/lists")
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
    "$found") nfound=$(( nfound + 1 )) ;;
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

[ "$nfound" -eq 0 ] || exit "$found"
[ "$unverified" = 0 ] || exit "$unverifiable"
exit "$clean"
