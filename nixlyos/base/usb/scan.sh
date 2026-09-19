#!/usr/bin/env bash
# Scan one freshly inserted USB filesystem before it may be mounted.
# $1 = kernel device name (sdb1).  Progress goes to
# /run/nixly-usbscan/<dev>.state, which nixlytile watches with inotify.
set -uo pipefail
# writeShellApplication forces errexit; this script guards its own exits.
set +o errexit

dev=$1
node=/dev/$dev
dir=/run/nixly-usbscan
state=$dir/$dev.state
mnt=$dir/mnt/$dev
batch_size=200

label=$(blkid -o value -s LABEL "$node" 2>/dev/null || true)
[ -n "$label" ] || label=$dev
size=$(lsblk -bdno SIZE "$node" 2>/dev/null || echo 0)
# The card belongs to the device, not the partition.
disk=$(lsblk -no PKNAME "$node" 2>/dev/null | head -1)
[ -n "$disk" ] || disk=$dev

files=0
done_n=0
threats=0
unscannable=0
scripts=0
cached=0
hits=0
found=""

# One atomic rewrite per update; a half-written state never reaches the reader.
put() {
  local tmp=$state.tmp
  {
    echo "state=$1"
    echo "dev=$dev"
    echo "disk=$disk"
    echo "label=$label"
    echo "size=$size"
    echo "files=$files"
    echo "done=$done_n"
    echo "threats=$threats"
    echo "unscannable=$unscannable"
    echo "scripts=$scripts"
    echo "cached=$cached"
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
# Root-only: the state files stay readable, the device does not.
chmod 700 "$dir/mnt"
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

# Start clamd for this scan and wait for the database load to finish.
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

# A file that scanned clean is remembered by its BLAKE3 content hash, keyed
# by the loaded signature set: a later insert re-hashes and skips anything
# unchanged, while an edited file gets a new hash and is scanned again. The
# key resets whenever the clamav database changes, so fresh signatures are
# always applied at least once to every file.
cacheroot=/var/lib/nixly-usbscan/hashes
epoch=$(stat -c '%s:%Y' /var/lib/clamav/*.c?d 2>/dev/null | b3sum --no-names 2>/dev/null | cut -c1-16)
[ -n "$epoch" ] || epoch=noepoch
cachedir=$cacheroot/$epoch
mkdir -p "$cachedir" 2>/dev/null
# A new signature set makes old verdicts stale; drop every other epoch.
find "$cacheroot" -mindepth 1 -maxdepth 1 -type d ! -name "$epoch" \
  -exec rm -rf {} + 2>/dev/null || true

remember() {
  local h=$1 sh
  [ -n "$h" ] || return 0
  sh=$cachedir/${h:0:2}
  mkdir -p "$sh" 2>/dev/null
  : >"$sh/$h" 2>/dev/null || true
}

put counting
files=$(find "$mnt" -xdev -type f -printf . 2>/dev/null | wc -c)
put scanning

declare -A fhash
batch=()
flush() {
  [ ${#batch[@]} -gt 0 ] || return 0
  local out line hit sig inner rc f
  local -A bad=() skip=()
  # --multiscan spreads the batch over clamd's threads; --fdpass hands it
  # open descriptors so it never re-opens a path under our feet.
  # A detection makes clamdscan exit nonzero; that is the normal case here.
  out=$(clamdscan --fdpass --multiscan --no-summary --infected "${batch[@]}" 2>/dev/null) || true
  if [ -n "$out" ]; then
    while IFS= read -r line; do
      hit=${line%%: *}
      # A file the engine could not read is never remembered as clean.
      if [ "${line%ERROR}" != "$line" ]; then
        skip["$hit"]=1
        continue
      fi
      sig=${line##*: }
      sig=${sig% FOUND}
      if [ "${sig#*Limits.Exceeded}" != "$sig" ]; then
        # Too big to read in one piece: unpack it and scan the parts.
        if inner=$(nixly-scan-expand "$hit"); then
          rc=0
        else
          rc=$?
        fi
        case $rc in
          0) continue ;;
          1) sig="contains $(head -1 <<<"$inner")"
             threats=$(( threats + 1 )); bad["$hit"]=1 ;;
          *) sig="too large to scan, could not be unpacked"
             unscannable=$(( unscannable + 1 )); skip["$hit"]=1 ;;
        esac
      else
        threats=$(( threats + 1 )); bad["$hit"]=1
      fi
      if [ "$hits" -lt 5 ]; then
        found="${found:+$found|}$(basename "$hit") — $sig"
        hits=$(( hits + 1 ))
      fi
    done < <(grep -E 'FOUND$|ERROR$' <<<"$out")
  fi
  # Everything in the batch that was neither infected nor unreadable is clean.
  for f in "${batch[@]}"; do
    [ -n "${bad[$f]:-}${skip[$f]:-}" ] || remember "${fhash[$f]:-}"
    unset 'fhash[$f]'
  done
  done_n=$(( done_n + ${#batch[@]} ))
  batch=()
  put scanning
}

while IFS= read -r -d '' f; do
  case ${f,,} in
    *autorun.inf|*.lnk|*.desktop|*.bat|*.cmd|*.vbs|*.vbe|*.ps1|*.scr|*.jse|*.hta)
      scripts=$(( scripts + 1 )) ;;
  esac
  h=$(b3sum --no-names -- "$f" 2>/dev/null)
  # Known-clean and unchanged: skip the scan, still count it as done.
  if [ -n "$h" ] && [ -e "$cachedir/${h:0:2}/$h" ]; then
    done_n=$(( done_n + 1 ))
    cached=$(( cached + 1 ))
    (( done_n % batch_size == 0 )) && put scanning
    continue
  fi
  batch+=("$f")
  fhash["$f"]=$h
  [ ${#batch[@]} -ge $batch_size ] && flush
done < <(find "$mnt" -xdev -type f -print0 2>/dev/null)
flush

umount "$mnt" 2>/dev/null
rmdir "$mnt" 2>/dev/null

if [ "$threats" -gt 0 ]; then
  put infected "$threats threat(s)"
elif [ "$unscannable" -gt 0 ]; then
  put unverified "$unscannable file(s) past the scan limits"
else
  put clean
fi

# Kill clamd the instant the last partition finishes — no idle 1 GB resident.
# A sibling scan still running keeps it up; that scan stops it when it ends.
siblings=$(systemctl list-units --plain --no-legend --state=active,activating \
  'nixly-usbscan@*.service' 2>/dev/null \
  | awk -v me="nixly-usbscan@$dev.service" '$1 ~ /nixly-usbscan@/ && $1 != me')
[ -n "$siblings" ] || systemctl stop --no-block clamav-daemon.service 2>/dev/null || true
true
