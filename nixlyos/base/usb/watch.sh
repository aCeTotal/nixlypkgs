#!/usr/bin/env bash
# Session side of the USB scanner: turns /run/nixly-usbscan/*.state into one
# slide-in card per device with a live progress bar, then mounts a clean
# device and opens it in the file manager.
set -uo pipefail

dir=/run/nixly-usbscan
declare -A nid
declare -A mounted

bar() {
  local pct=$1 filled=$(( $1 * 16 / 100 )) i out=""
  for (( i = 0; i < 16; i++ )); do
    if [ "$i" -lt "$filled" ]; then out+="█"; else out+="░"; fi
  done
  printf '%s %d%%' "$out" "$pct"
}

human() {
  numfmt --to=iec --suffix=B "${1:-0}" 2>/dev/null || echo "?"
}

toast() {
  local dev=$1 hold=$2 summary=$3 body=$4
  if [ -n "${nid[$dev]:-}" ]; then
    notify-send -a NixlyOS -t "$hold" --replace-id="${nid[$dev]}" \
      "$summary" "$body"
  else
    nid[$dev]=$(notify-send -a NixlyOS -t "$hold" -p "$summary" "$body")
  fi
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
  nautilus --new-window "$target" >/dev/null 2>&1 &
  return 0
}

render() {
  local f=$1 state="" dev="" label="" size=0 files=0 done_n=0 threats=0
  local scripts=0 found="" msg="" k v pct=0

  [ -r "$f" ] || return 0
  while IFS='=' read -r k v; do
    case $k in
      state) state=$v ;; dev) dev=$v ;; label) label=$v ;;
      size) size=$v ;; files) files=$v ;; done) done_n=$v ;;
      threats) threats=$v ;; scripts) scripts=$v ;; found) found=$v ;;
      msg) msg=$v ;;
    esac
  done <"$f"
  [ -n "$dev" ] || return 0
  [ "$files" -gt 0 ] && pct=$(( done_n * 100 / files ))

  case $state in
    detected|updating|starting)
      toast "$dev" 30000 "USB oppdaget · $label" \
        "$(human "$size") — gjør klar skanning" ;;
    counting)
      toast "$dev" 30000 "Skanner $label" "Teller filer…" ;;
    scanning)
      toast "$dev" 60000 "Skanner $label" \
        "$(bar "$pct")
$done_n av $files filer" ;;
    clean)
      local note="$files filer skannet, ingen trusler"
      [ "$scripts" -gt 0 ] && note="$note
$scripts script/snarvei funnet (kan ikke kjøres herfra)"
      if do_mount "$dev" "$label"; then
        toast "$dev" 6000 "USB klar · $label" "$note"
      else
        toast "$dev" 8000 "USB ren · $label" \
          "Skanning OK, men montering feilet"
      fi ;;
    infected)
      toast "$dev" 60000 "⚠ Trusler på $label" \
        "$threats funn — ikke montert
${found:-ukjent signatur}" ;;
    unreadable|unavailable)
      toast "$dev" 10000 "USB ikke skannet · $label" "${msg:-ukjent feil}" ;;
  esac
}

for f in "$dir"/*.state; do
  [ -e "$f" ] && render "$f"
done

inotifywait -q -m -e close_write,moved_to,delete --format '%e %f' "$dir" \
| while read -r ev file; do
  case $file in *.state) ;; *) continue ;; esac
  case $ev in
    DELETE)
      dev=${file%.state}
      unset 'nid[$dev]' 'mounted[$dev]' ;;
    *) render "$dir/$file" ;;
  esac
done
