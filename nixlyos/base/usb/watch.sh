#!/usr/bin/env bash
# Session side of the USB scanner: one card per device, never per partition.
# Isolated while it is being verified, then mounted or blocked.
set -uo pipefail
# writeShellApplication forces errexit; this script guards its own exits.
set +o errexit

dir=/run/nixly-usbscan
declare -A nid card mounted opened

# Fields of the state file last read by load().
f_state="" f_dev="" f_disk="" f_label="" f_threats=0 f_unscannable=0
f_found="" f_msg=""

load() {
  local k v
  f_state=""; f_dev=""; f_disk=""; f_label=""; f_threats=0; f_unscannable=0
  f_found=""; f_msg=""
  [ -r "$1" ] || return 1
  while IFS='=' read -r k v; do
    case $k in
      state) f_state=$v ;; dev) f_dev=$v ;; disk) f_disk=$v ;;
      label) f_label=$v ;; threats) f_threats=$v ;;
      unscannable) f_unscannable=$v ;;
      found) f_found=$v ;; msg) f_msg=$v ;;
    esac
  done <"$1"
  [ -n "$f_dev" ] || return 1
  [ -n "$f_disk" ] || f_disk=$f_dev
  return 0
}

toast() {
  local d=$1 urgency=$2 hold=$3 summary=$4 body=$5
  if [ -n "${nid[$d]:-}" ]; then
    notify-send -a NixlyOS -u "$urgency" -t "$hold" \
      --replace-id="${nid[$d]}" "$summary" "$body"
  else
    nid[$d]=$(notify-send -a NixlyOS -u "$urgency" -t "$hold" -p "$summary" "$body")
  fi
}

# How many filesystems udev will hand to the scanner for this device.
expected() {
  local d=$1 n=0 name fs
  while read -r name fs; do
    [ "$name" != "$d" ] || continue
    case $fs in ""|crypto_LUKS|LVM2_member) continue ;; esac
    n=$(( n + 1 ))
  done < <(lsblk -rno NAME,FSTYPE "/dev/$d" 2>/dev/null)
  [ "$n" -gt 0 ] || n=1
  echo "$n"
}

name_of() {
  local d=$1 model
  model=$(lsblk -dno MODEL "/dev/$d" 2>/dev/null | sed 's/ *$//')
  [ -n "$model" ] || model="USB device"
  echo "$model"
}

# Hand the device to nixly-diskd, which mounts it nosuid,nodev,noexec.
do_mount() {
  local dev=$1 label=$2 fstype target
  [ -z "${mounted[$dev]:-}" ] || return 0
  fstype=$(lsblk -no FSTYPE "/dev/$dev" 2>/dev/null | head -1)
  [ -n "$fstype" ] || fstype=auto
  target="/run/media/$USER/$(tr -c '[:alnum:]._-' '_' <<<"$label" | cut -c1-40)"
  printf 'mount %s /dev/%s %s %s\n' "$fstype" "$dev" "$target" "$(id -u)" \
    | socat -t2 - UNIX-CONNECT:/run/nixly-diskd.sock >/dev/null 2>&1
  mountpoint -q "$target" || return 1
  mounted[$dev]=$target
  return 0
}

render() {
  local d=$1 f i seen=0 pending=0 threats=0 unscannable=0
  local findings="" blocked="" extra=""
  local clean=() labels=() name target

  for f in "$dir"/*.state; do
    load "$f" || continue
    [ "$f_disk" = "$d" ] || continue
    seen=$(( seen + 1 ))
    case $f_state in
      detected|updating|starting|counting|scanning)
        pending=1 ;;
      infected)
        threats=$(( threats + f_threats ))
        findings="${findings:+$findings|}$f_found" ;;
      unverified)
        unscannable=$(( unscannable + f_unscannable ))
        findings="${findings:+$findings|}$f_found" ;;
      clean)
        clean+=("$f_dev"); labels+=("$f_label") ;;
      *)
        blocked=${f_msg:-could not be read} ;;
    esac
  done

  [ "$seen" -gt 0 ] || return 0
  name=$(name_of "$d")

  # Scanning is silent: the device is simply not there yet.
  if [ "$pending" = 1 ] || [ "$seen" -lt "$(expected "$d")" ]; then
    card[$d]=scanning
    return 0
  fi

  if [ "$threats" -gt 0 ]; then
    card[$d]=blocked
    # Only the first five findings are carried in the state file.
    [ "$threats" -gt 5 ] && extra=$(( threats - 5 ))
    toast "$d" critical 0 "USB device blocked" \
      "$name was not mounted — $threats threat(s) found

$(tr '|' '\n' <<<"$findings")${extra:+
+$extra more}"
    return 0
  fi

  if [ "$unscannable" -gt 0 ]; then
    card[$d]=blocked
    toast "$d" critical 0 "USB device blocked" \
      "$name was not mounted — $unscannable file(s) could not be scanned

$(tr '|' '\n' <<<"$findings")"
    return 0
  fi

  if [ -n "$blocked" ]; then
    card[$d]=blocked
    toast "$d" critical 0 "USB device blocked" \
      "$name could not be verified — $blocked"
    return 0
  fi

  [ "${card[$d]:-}" = verified ] && return 0
  target=""
  for i in "${!clean[@]}"; do
    if do_mount "${clean[$i]}" "${labels[$i]}"; then
      target=${target:-${mounted[${clean[$i]}]}}
    fi
  done
  card[$d]=verified
  # A clean device just opens, without announcing itself.
  if [ -n "$target" ]; then
    if [ -z "${opened[$d]:-}" ]; then
      opened[$d]=1
      nautilus --new-window "$target" >/dev/null 2>&1 &
    fi
  else
    toast "$d" critical 0 "USB device blocked" \
      "$name passed the scan but could not be mounted"
  fi
}

disks() {
  local f
  for f in "$dir"/*.state; do
    load "$f" && echo "$f_disk"
  done | sort -u
  return 0
}

# A card dies with the last state file of its device.
forget() {
  local live d
  live=$(disks)
  for d in "${!card[@]}"; do
    grep -qx "$d" <<<"$live" && continue
    unset 'card[$d]' 'nid[$d]' 'opened[$d]'
  done
}

sweep() {
  local d
  for d in $(disks); do render "$d"; done
}

# The runtime dir only exists once the first scan runs; wait for it and
# re-arm if the watch ever drops, so login before any insert never kills us.
while true; do
  [ -d "$dir" ] || { sleep 2; continue; }
  sweep
  while read -r ev file; do
    case $file in *.state) ;; *) continue ;; esac
    case $ev in *DELETE*) forget; continue ;; esac
    sweep
  done < <(inotifywait -q -m -e close_write,moved_to,delete --format '%e %f' "$dir")
  sleep 2
done
