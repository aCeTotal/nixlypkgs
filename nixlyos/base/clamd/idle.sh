#!/usr/bin/env bash
# Stop clamd once nothing scans.
set -uo pipefail

sock=/run/clamav/clamd.ctl
grace=30
idle=0

# Open or queued clients.
busy() {
  ss -xHa src "$sock" | awk '$2 != "LISTEN" || $3 > 0 { f = 1 } END { exit !f }'
}

while sleep 1; do
  if busy; then
    idle=0
    continue
  fi
  idle=$(( idle + 1 ))
  [ "$idle" -lt "$grace" ] || exec systemctl stop --no-block clamav-daemon.service
done
