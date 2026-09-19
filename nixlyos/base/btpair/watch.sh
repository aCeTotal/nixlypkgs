#!/usr/bin/env bash
# Drop bonds the peer no longer holds.

events=/run/nixly-bt/events
mkdir -p /run/nixly-bt
chmod 755 /run/nixly-bt
: >"$events"
chmod 644 "$events"

declare -A fails
hit=0

stdbuf -oL btmon --no-pager 2>/dev/null | while read -r line; do
  if [[ $line == *"PIN or Key Missing"* ]]; then
    hit=1
    continue
  fi

  if [[ $hit != 1 || $line != *"Address: "* ]]; then
    continue
  fi
  hit=0

  mac=${line#*Address: }
  mac=${mac%% *}

  # One rejection can be a race; a dead key fails every time.
  count=$(( ${fails[$mac]:-0} + 1 ))
  fails[$mac]=$count
  if (( count < 3 )); then
    continue
  fi
  fails[$mac]=0

  name=$(bluetoothctl info "$mac" | sed -n 's/^[[:space:]]*Name: //p' | head -1)
  bluetoothctl remove "$mac" >/dev/null 2>&1 || true
  printf '%s|%s\n' "$mac" "${name:-$mac}" >>"$events"
  nixly-btpair "$mac" >/dev/null 2>&1 &
done
