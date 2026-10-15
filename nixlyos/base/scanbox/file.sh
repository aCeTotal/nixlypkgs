#!/usr/bin/env bash
# Verdict for one file.
# stdout: the threat, or why it is unverified.
# fd 3, when open: progress lines.
# 0 clean, 1 threat, 2 unverified.
set -uo pipefail

f=$1
limit=$(( 2 * 1024 * 1024 * 1024 ))

# clamd stops at 2G.
expanded() {
  local out rc=0
  out=$(nixly-scan-expand "$f") || rc=$?
  [ "$rc" = 0 ] || printf '%s\n' "${out:-too large to scan and could not be unpacked}" | head -1
  exit "$rc"
}

[ "$(stat -c %s -- "$f")" -le "$limit" ] || expanded

rc=0
out=$(clamdscan --fdpass --no-summary --infected --wait --ping 120:1 -- "$f" 2>/dev/null) || rc=$?
out=${out##*: }
out=${out% FOUND}
case $rc:$out in
  0:*) exit 0 ;;
  1:*ncrypted*|1:*Limits.Exceeded*) rc=2 ;;
  1:*) ;;
  *) out="could not be scanned" rc=2 ;;
esac
printf '%s\n' "$out"
exit "$rc"
