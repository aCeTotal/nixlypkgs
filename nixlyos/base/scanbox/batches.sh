#!/usr/bin/env bash
# Parallel clamd batches from stdin.
set -uo pipefail

dir=$1
batch_bytes=$(( 64 * 1024 * 1024 ))
batch_files=256
# Idle flush for partial batches.
idle_s=1

jobs=$(nproc)
running=0
n=0
size=0
count=0
fd=""

run() {
  local rc=0
  clamdscan --fdpass --no-summary --infected -f "$1" 2>/dev/null || rc=$?
  echo "batch $2 $rc $1"
}

flush() {
  [ "$count" -gt 0 ] || return 0
  exec {fd}>&-
  if [ "$running" -ge "$jobs" ]; then
    wait -n
  else
    running=$(( running + 1 ))
  fi
  run "$dir/$n" "$size" &
  n=$(( n + 1 ))
  size=0
  count=0
}

add() {
  [ "$count" -gt 0 ] || exec {fd}>"$dir/$n"
  printf '%s\n' "$2" >&"$fd"
  size=$(( size + $1 ))
  count=$(( count + 1 ))
  [ "$size" -lt "$batch_bytes" ] && [ "$count" -lt "$batch_files" ] || flush
}

while true; do
  rc=0
  IFS=$'\t' read -r -d '' -t "$idle_s" bytes path || rc=$?
  case $rc in
    0) add "$bytes" "$path" ;;
    1) break ;;
    *) flush ;;
  esac
done
flush
wait
