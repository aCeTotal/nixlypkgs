#!/usr/bin/env bash
# Scan one freshly inserted USB filesystem before it may be mounted.
# $1 = kernel device name (sdb1).  Progress goes to
# /run/nixly-usbscan/<dev>.state, which nixlytile watches with inotify.
set -uo pipefail

dev=$1
node=/dev/$dev
dir=/run/nixly-usbscan
state=$dir/$dev.state
mnt=$dir/mnt/$dev
batch_size=200
clamd_linger=600

label=$(blkid -o value -s LABEL "$node" 2>/dev/null || true)
[ -n "$label" ] || label=$dev
size=$(lsblk -bdno SIZE "$node" 2>/dev/null || echo 0)

files=0
done_n=0
threats=0
scripts=0
found=""

# One atomic rewrite per update; a half-written state never reaches the reader.
put() {
  local tmp=$state.tmp
  {
    echo "state=$1"
    echo "dev=$dev"
    echo "label=$label"
    echo "size=$size"
    echo "files=$files"
    echo "done=$done_n"
    echo "threats=$threats"
    echo "scripts=$scripts"
    echo "found=$found"
    echo "msg=${2:-}"
  } >"$tmp"
  mv -f "$tmp" "$state"
}

cleanup() {
  mountpoint -q "$mnt" && umount "$mnt" 2>/dev/null
  rmdir "$mnt" 2>/dev/null
  true
}
trap cleanup EXIT

mkdir -p "$dir/mnt"
put detected

# Newest signatures without paying for them: the refresh runs alongside the
# scan, so a device inserted an hour after the last update still gets today's
# definitions on the next one rather than a stalled progress bar now.
systemctl start --no-block clamav-freshclam.service 2>/dev/null
systemctl start --no-block clamav-fangfrisch.service 2>/dev/null

if [ ! -s /var/lib/clamav/daily.cvd ] && [ ! -s /var/lib/clamav/daily.cld ]; then
  put updating
  systemctl start --wait clamav-freshclam.service 2>/dev/null
fi
if [ ! -s /var/lib/clamav/daily.cvd ] && [ ! -s /var/lib/clamav/daily.cld ]; then
  put unavailable "no signature database"
  exit 0
fi

# udev started clamd the moment the device appeared; this only waits for the
# database load to finish.
put starting
systemctl start --no-block clamav-daemon.service 2>/dev/null
if ! clamdscan --ping 120 >/dev/null 2>&1; then
  put unavailable "scanner did not start"
  exit 0
fi

mkdir -p "$mnt"
if ! mount -o ro,nosuid,nodev,noexec "$node" "$mnt" 2>/dev/null; then
  put unreadable "cannot mount read-only"
  exit 0
fi

put counting
files=$(find "$mnt" -xdev -type f -printf . 2>/dev/null | wc -c)
put scanning

batch=()
flush() {
  [ ${#batch[@]} -gt 0 ] || return 0
  local out hit
  # --multiscan spreads the batch over clamd's threads; --fdpass hands it
  # open descriptors so it never re-opens a path under our feet.
  out=$(clamdscan --fdpass --multiscan --no-summary --infected "${batch[@]}" 2>/dev/null)
  if [ -n "$out" ]; then
    threats=$(( threats + $(grep -c 'FOUND$' <<<"$out") ))
    hit=$(grep -m1 'FOUND$' <<<"$out" | sed 's/.*: //; s/ FOUND$//')
    [ -n "$found" ] || found=$hit
  fi
  done_n=$(( done_n + ${#batch[@]} ))
  batch=()
  put scanning
}

while IFS= read -r -d '' f; do
  case ${f,,} in
    *autorun.inf|*.lnk|*.desktop|*.bat|*.cmd|*.vbs|*.vbe|*.ps1|*.scr|*.jse|*.hta)
      scripts=$(( scripts + 1 )) ;;
  esac
  batch+=("$f")
  [ ${#batch[@]} -ge $batch_size ] && flush
done < <(find "$mnt" -xdev -type f -print0 2>/dev/null)
flush

umount "$mnt" 2>/dev/null
rmdir "$mnt" 2>/dev/null

if [ "$threats" -gt 0 ]; then
  put infected "$threats threat(s)"
else
  put clean
fi

# Keep the loaded signature set around: plugging in a second stick within the
# next few minutes then scans instantly instead of reloading ~1 GB.
systemctl stop nixly-clamd-stop.timer 2>/dev/null
systemd-run --quiet --unit=nixly-clamd-stop --on-active=$clamd_linger \
  systemctl stop clamav-daemon.service 2>/dev/null
true
