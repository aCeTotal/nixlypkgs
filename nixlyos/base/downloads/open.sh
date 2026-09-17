#!/usr/bin/env bash
# Open a held file with no network, no home and nothing else reachable.
set -uo pipefail

q=/var/lib/nixly-quarantine

if [ $# -ne 1 ]; then
  echo "held files:"
  ls -1 "$q" 2>/dev/null
  echo
  echo "nixly-open-held <name>"
  exit 0
fi

name=$(basename -- "$1")
[ -r "$q/$name" ] || { echo "not held: $name" >&2; exit 1; }

box=$(mktemp -d)
trap 'rm -rf "$box"' EXIT
cp -- "$q/$name" "$box/$name"
chmod 400 "$box/$name"

/run/wrappers/bin/firejail --quiet --noprofile --net=none --caps.drop=all --nonewprivs \
  --private="$box" -- file-roller "$name"
