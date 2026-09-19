#!/usr/bin/env bash
# Say which pad needs its sync button.

events=/run/nixly-bt/events

tail -F -n0 "$events" 2>/dev/null | while IFS='|' read -r _ name; do
  notify-send -u critical -a NixlyOS -t 0 "Controller lost its pairing" \
    "$name
Hold the sync button until the logo flashes — it re-pairs on its own."
done
