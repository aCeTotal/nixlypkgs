#!/usr/bin/env bash
# Open a file clamd cannot take in one piece and scan what is inside it.
# Filesystem and VM images are mounted, everything else is unpacked; the
# unpacked copy is deleted the moment the scan is over, in every exit path.
# stdout: one "name — reason" line per finding.
# 0 = clean, 1 = something found, 2 = nothing could be opened.
set -uo pipefail

f=$1
depth=${2:-0}
box=/var/lib/nixly-scanbox
max_depth=2
limit=$(( 2 * 1024 * 1024 * 1024 ))
headroom=$(( 2 * 1024 * 1024 * 1024 ))

nfound=0
unverified=0
opened=0
loop=""

[ -r "$f" ] || exit 2
[ "$depth" -le "$max_depth" ] || exit 2

work=$(mktemp -d "$box/XXXXXXXX" 2>/dev/null) || exit 2
chmod 700 "$work"
mkdir -p "$work/mnt" "$work/x"

cleanup() {
  mountpoint -q "$work/mnt" && umount -R "$work/mnt" 2>/dev/null
  [ -z "$loop" ] || losetup -d "$loop" 2>/dev/null
  rm -rf "$work"
}
trap cleanup EXIT INT TERM HUP

record() {
  printf '%s — %s\n' "$(basename -- "$1")" "$2"
  nfound=$(( nfound + 1 ))
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

scan_tree() {
  local dir=$1 out line p s sub rc
  # clamdscan exits nonzero on a detection, which is not an error here.
  out=$(clamdscan --fdpass --multiscan --no-summary --infected "$dir" 2>/dev/null) || true
  while IFS= read -r line; do
    case $line in *" FOUND") ;; *) continue ;; esac
    p=${line%%: *}
    s=${line##*: }
    s=${s% FOUND}
    case $s in
      *Limits.Exceeded*) ;;
      *) record "$p" "$s" ;;
    esac
  done <<<"$out"

  # Anything still too big for the engine gets the same treatment again.
  while IFS= read -r -d '' big; do
    if sub=$("$0" "$big" "$(( depth + 1 ))"); then
      rc=0
    else
      rc=$?
    fi
    case $rc in
      0) ;;
      1) printf '%s' "$sub"; nfound=$(( nfound + 1 )) ;;
      *) note "$big" "could not be opened" ;;
    esac
  done < <(find "$dir" -xdev -type f -size +"$limit"c -print0 2>/dev/null)
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
  if bsdtar -xf "$f" -C "$work/x" 2>/dev/null ||
      7zz x -y -bso0 -bsp0 -o"$work/x" "$f" >/dev/null 2>&1 ||
      unsquashfs -n -f -d "$work/x" "$f" >/dev/null 2>&1 ||
      wimextract "$f" all --dest-dir="$work/x" >/dev/null 2>&1 ||
      innoextract -s -d "$work/x" "$f" >/dev/null 2>&1 ||
      cabextract -q -d "$work/x" "$f" >/dev/null 2>&1 ||
      (rpm2cpio "$f" 2>/dev/null | cpio -idmu --quiet -D "$work/x" 2>/dev/null) ||
      (dmg2img -s "$f" "$work/raw" >/dev/null 2>&1 &&
        mount -o ro,nosuid,nodev,noexec,loop "$work/raw" "$work/mnt" 2>/dev/null &&
        mount_and_scan)
  then
    if [ "$opened" = 0 ] && [ -n "$(ls -A "$work/x" 2>/dev/null)" ]; then
      opened=1
      scan_tree "$work/x"
    fi
  fi
fi

rc=0
if [ "$opened" = 0 ] || [ "$unverified" != 0 ]; then
  rc=2
fi
[ "$nfound" -eq 0 ] || rc=1

# The unpacked copy never outlives the scan.
cleanup
exit "$rc"
