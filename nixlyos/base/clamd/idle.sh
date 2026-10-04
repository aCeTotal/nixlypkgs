#!/usr/bin/env bash
# Stop clamd once nothing scans.
set -uo pipefail

sock=/run/clamav/clamd.ctl
grace=2
idle=0

# Open clients, queued clients or a USB scan.
busy() {
  ss -xHa src "$sock" | awk '$2 != "LISTEN" || $3 > 0 { f = 1 } END { exit !f }' && return 0
  [ -n "$(systemctl list-units --plain --no-legend --state=active,activating 'nixly-usbscan@*')" ]
}

while sleep 1; do
  if busy; then
    idle=0
    continue
  fi
  idle=$(( idle + 1 ))
  [ "$idle" -lt "$grace" ] || exec systemctl stop --no-block clamav-daemon.service
done
