#!/usr/bin/env bash
# Background staging: eval, download and build the NEXT system generation
# while the machine is idle, kept alive by a GC root. nixlyos-update then
# finds the finished build and only has to activate it — seconds, not minutes.
# Runs from a systemd timer; safe to run manually as `nixlyos-stage`.
set -euo pipefail

FLAKE="${NIXLYOS_DIR:-$HOME/.local/nixlyos}"
STAGE="${XDG_STATE_HOME:-$HOME/.local/state}/nixlyos/stage"
[[ -f "$FLAKE/flake.nix" ]] || exit 0

# Stay invisible: never compete with an interactive session under load, and
# never burn battery. No online files at all means desktop — proceed.
read -r load _ < /proc/loadavg
cores=$(nproc)
awk -v l="$load" -v c="$cores" 'BEGIN { exit !(l > c / 2) }' && exit 0
ac_files=0 ac_online=0
for f in /sys/class/power_supply/*/online; do
  [[ -r $f ]] || continue
  ac_files=1
  read -r v < "$f"; [[ $v == 1 ]] && ac_online=1
done
(( ac_files == 1 && ac_online == 0 )) && exit 0

# Exact copy of the flake files, nothing else: identical content means an
# identical flake fingerprint, so the update-time eval hits the cache too.
mkdir -p "$STAGE"
rm -rf "$STAGE/flake"
mkdir -p "$STAGE/flake"
cp "$FLAKE/flake.nix" "$FLAKE/local.nix" "$STAGE/flake/"
cp -r "$FLAKE/hardware" "$STAGE/flake/hardware"

# Exactly the same locking as nixlyos-update, or the staged key never
# matches: fresh lock (inherits nixlypkgs' tested pins), then nixpkgs stable
# and home-manager to their branch heads.
nix flake lock --flake "$STAGE/flake" >/dev/null 2>&1 || exit 0
nix flake update nixlypkgs/nixos-stable nixlypkgs/home-manager --flake "$STAGE/flake" >/dev/null 2>&1 || exit 0

# Pre-sized Boehm heap: the eval allocates gigabytes; starting big avoids
# hundreds of GC cycles and cuts eval time by a third or more.
export GC_INITIAL_HEAP_SIZE=2G

# Same file list and order as tree_key in update.sh.
key=$(cat "$STAGE/flake"/flake.nix "$STAGE/flake"/flake.lock "$STAGE/flake"/local.nix "$STAGE/flake"/hardware/* 2>/dev/null | sha1sum | cut -d' ' -f1)
if [[ -f "$STAGE/key" && "$(<"$STAGE/key")" == "$key" && -e "$STAGE/result" ]]; then
  exit 0
fi

# The out-link is the GC root that keeps the staged system alive until it is
# either activated or replaced by the next staging round. Gentle resource use:
# the unit runs at idle priority; substitution stays at nix defaults.
nix build --keep-going --out-link "$STAGE/result" \
  --option connect-timeout 3 \
  --option fallback true \
  "$STAGE/flake#nixosConfigurations.nixlyos.config.system.build.toplevel" \
  >/dev/null 2>&1 || exit 0

printf '%s\n' "$key" > "$STAGE/key"
