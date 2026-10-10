#!/usr/bin/env bash
# Scan inside files clamd refuses.
# stdout: first "name — reason" finding.
# fd 3, when open: progress lines.
# 0 clean, 1 found, 2 unopenable.
set -uo pipefail

f=$1
src=$(readlink -f -- "$f")
depth=${2:-0}
# Hashes already scanned, optional.
seen=${3:-}
box=/var/lib/nixly-scanbox
max_depth=2
limit=$(( 2 * 1024 * 1024 * 1024 ))
headroom=$(( 2 * 1024 * 1024 * 1024 ))

unverified=0
opened=0
loop=""
shown=""
report=0
[ ! -w /dev/fd/3 ] || report=1

[ -r "$f" ] || exit 2
[ "$depth" -le "$max_depth" ] || exit 2

work=$(mktemp -d "$box/XXXXXXXX" 2>/dev/null) || exit 2
chmod 700 "$work"
mkdir -p "$work/mnt" "$work/x"

cleanup() {
  mountpoint -q "$work/mnt" && umount -lR "$work/mnt" 2>/dev/null
  [ -z "$loop" ] || losetup -d "$loop" 2>/dev/null
  rm -rf "$work"
}
trap cleanup EXIT INT TERM HUP

progress() {
  local pct=$(( $2 * 100 / ($3 > 0 ? $3 : 1) ))
  [ "$report" = 1 ] && [ "$1 $pct" != "$shown" ] || return 0
  shown="$1 $pct"
  printf '%s %s %s %s\n' "$1" "$pct" "$2" "$3" >&3
}

# Unpacker read offset in source.
read_pos() {
  local fd pos
  for fd in /proc/"$1"/fd/*; do
    [ "$(readlink -- "$fd" 2>/dev/null)" = "$src" ] || continue
    read -r _ pos <"/proc/$1/fdinfo/${fd##*/}" || return 1
    printf '%s' "$pos"
    return 0
  done
  return 1
}

unpack() {
  local pid pos size
  size=$(stat -c %s -- "$f")
  "$@" >/dev/null 2>&1 &
  pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    if pos=$(read_pos "$pid"); then
      progress unpack "$pos" "$size"
    fi
    sleep 0.25
  done
  wait "$pid"
}

# First threat ends the scan.
record() {
  printf '%s — %s\n' "$(basename -- "$1")" "$2"
  exit 1
}

# Printed like a finding, but it is a gap in coverage, not a detection.
note() {
  printf '%s — %s\n' "$(basename -- "$1")" "$2"
  unverified=1
}

room_for() {
  local need=$1 avail
  avail=$(df -B1 --output=avail "$box" 2>/dev/null | tail -1) || avail=""
  [ -n "$avail" ] && [ "$avail" -gt "$(( need + headroom ))" ]
}

big=()
total=0
scanned=0

index_tree() {
  local size p
  big=()
  total=0
  scanned=0
  while IFS=$'\t' read -r -d '' size p; do
    total=$(( total + size ))
    if [ "$size" -gt "$limit" ]; then
      big+=("$p")
      continue
    fi
    printf '%s\t%s\0' "$size" "$p"
  done < <(find "$1" -xdev -type f -printf '%s\t%p\0' 2>/dev/null) >"$work/small"
}

# Every batch must report back.
verdict_line() {
  local s bytes rc
  case $1 in
    "batch "*)
      read -r _ bytes rc _ <<<"$1"
      [ "$rc" != 2 ] || note "$2" "some files could not be scanned"
      scanned=$(( scanned + bytes ))
      progress scan "$scanned" "$total" ;;
    *" FOUND")
      s=${1##*: }
      s=${s% FOUND}
      case $s in *Limits.Exceeded*) ;; *) record "${1%: *}" "$s" ;; esac ;;
  esac
}

# Recurse into oversized members.
scan_big() {
  local sub rc=0
  sub=$("$0" "$1" "$(( depth + 1 ))" 3>&-) || rc=$?
  case $rc in
    0) ;;
    1) printf '%s' "$sub"; exit 1 ;;
    *) note "$1" "could not be opened" ;;
  esac
  scanned=$(( scanned + $(stat -c %s -- "$1") ))
  progress scan "$scanned" "$total"
}

scan_tree() {
  local line p
  index_tree "$1"
  mkdir -p "$work/lists"
  progress scan 0 "$total"
  while IFS= read -r line; do
    verdict_line "$line" "$1"
  done < <(nixly-scan-batches "$work/lists" <"$work/small" 3>&-)
  for p in "${big[@]}"; do
    scan_big "$p"
  done
}

# Skip members scanned while downloading.
drop_seen() {
  local h p size got=0 all=0
  local -A known bytes
  while read -r h; do
    known[$h]=1
  done <"$seen"
  while IFS=$'\t' read -r -d '' size p; do
    bytes[$p]=$size
    all=$(( all + size ))
  done < <(find "$1" -type f -printf '%s\t%p\0')
  while read -r h p; do
    [ -z "${known[$h]:-}" ] || rm -f -- "$p"
    got=$(( got + ${bytes[$p]:-0} ))
    progress match "$got" "$all"
  done < <(find "$1" -type f -print0 | xargs -0 -r -P "$(nproc)" -n 256 b3sum --)
}

mount_and_scan() {
  mountpoint -q "$work/mnt" || return 1
  opened=1
  scan_tree "$work/mnt"
  umount -R "$work/mnt" 2>/dev/null
  return 0
}

scan_partitions() {
  local dev=$1 part
  for part in "$dev"p*; do
    [ -b "$part" ] || continue
    mount -o ro,nosuid,nodev,noexec "$part" "$work/mnt" 2>/dev/null &&
      mount_and_scan
  done
}

# 1. A filesystem in a file: iso, udf, squashfs, ext, ntfs, vfat, btrfs…
if mount -o ro,nosuid,nodev,noexec,loop "$f" "$work/mnt" 2>/dev/null; then
  mount_and_scan
fi

# 2. A whole disk in a file, partition table and all.
if [ "$opened" = 0 ]; then
  loop=$(losetup -Pf --show -r "$f" 2>/dev/null) || loop=""
  if [ -n "$loop" ]; then
    scan_partitions "$loop"
    losetup -d "$loop" 2>/dev/null
    loop=""
  fi
fi

# 3. A virtual disk: qcow2, vmdk, vhd, vhdx, vdi. Raw already failed above.
if [ "$opened" = 0 ] && qemu-img info --output=json "$f" 2>/dev/null \
    | grep -q '"format": "\(qcow2\|vmdk\|vhdx\|vpc\|vdi\|parallels\|qed\)"'; then
  size=$(qemu-img info --output=json "$f" 2>/dev/null \
    | grep -o '"virtual-size": *[0-9]*' | grep -o '[0-9]*' | head -1) || size=0
  if room_for "${size:-0}" &&
      qemu-img convert -O raw "$f" "$work/raw" 2>/dev/null; then
    loop=$(losetup -Pf --show -r "$work/raw" 2>/dev/null) || loop=""
    if [ -n "$loop" ]; then
      mount -o ro,nosuid,nodev,noexec "$loop" "$work/mnt" 2>/dev/null &&
        mount_and_scan
      [ "$opened" = 1 ] || scan_partitions "$loop"
      losetup -d "$loop" 2>/dev/null
      loop=""
    fi
    rm -f "$work/raw"
  fi
fi

# 4. Everything else is an archive of some kind. libarchive covers tar in
#    every compression, zip, 7z, cab, cpio, ar, xar, lha and rar; the rest
#    have their own openers.
if [ "$opened" = 0 ] && room_for "$(stat -c %s -- "$f" 2>/dev/null || echo 0)"; then
  if unpack bsdtar -xf "$f" -C "$work/x" ||
      unpack 7zz x -y -bso0 -bsp0 -o"$work/x" "$f" ||
      unpack unsquashfs -n -f -d "$work/x" "$f" ||
      unpack wimextract "$f" all --dest-dir="$work/x" ||
      unpack innoextract -s -d "$work/x" "$f" ||
      unpack cabextract -q -d "$work/x" "$f" ||
      (rpm2cpio "$f" 2>/dev/null | cpio -idmu --quiet -D "$work/x" 2>/dev/null) ||
      (dmg2img -s "$f" "$work/raw" >/dev/null 2>&1 &&
        mount -o ro,nosuid,nodev,noexec,loop "$work/raw" "$work/mnt" 2>/dev/null &&
        mount_and_scan)
  then
    if [ "$opened" = 0 ] && [ -n "$(ls -A "$work/x" 2>/dev/null)" ]; then
      opened=1
      [ -z "$seen" ] || drop_seen "$work/x"
      scan_tree "$work/x"
    fi
  fi
fi

rc=0
if [ "$opened" = 0 ] || [ "$unverified" != 0 ]; then
  rc=2
fi

# The unpacked copy never outlives the scan.
cleanup
exit "$rc"
