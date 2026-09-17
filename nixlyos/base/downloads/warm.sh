#!/usr/bin/env bash
# Keep clamd off until a download appears, then off again ten minutes later.
set -uo pipefail

linger=600

arm() {
  systemctl stop nixly-clamd-stop.timer 2>/dev/null || true
  systemd-run --quiet --unit=nixly-clamd-stop --on-active=$linger \
    systemctl stop clamav-daemon.service 2>/dev/null || true
}

arm

inotifywait -q -m -e create,moved_to --format . "$@" 2>/dev/null \
| while read -r _; do
  systemctl start --no-block clamav-daemon.service 2>/dev/null
  arm
done
