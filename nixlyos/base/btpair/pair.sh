#!/usr/bin/env bash
# Pair from a TTY; one-shot bluetoothctl registers no agent.

mac=${1:-}
if [[ -z $mac ]]; then
  echo "usage: nixly-btpair <mac>" >&2
  exit 1
fi

window=${NIXLY_BTPAIR_WINDOW:-180}

{
  echo "agent NoInputNoOutput"
  sleep 1
  echo "scan on"

  waited=0
  while (( waited < window )); do
    sleep 3
    waited=$(( waited + 3 ))
    if bluetoothctl info "$mac" | grep -q "Alias:"; then
      break
    fi
  done

  echo "pair $mac"
  sleep 12
  echo "trust $mac"
  sleep 1
  echo "connect $mac"
  sleep 8
  echo "quit"
} | bluetoothctl >/dev/null 2>&1

bluetoothctl info "$mac" | grep -q "Connected: yes"
