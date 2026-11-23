#!/usr/bin/env bash
# Prebuilds the next generation while idle.
set -euo pipefail

FLAKE="${NIXLYOS_DIR:-$HOME/.local/nixlyos}"
STAGE="${XDG_STATE_HOME:-$HOME/.local/state}/nixlyos/stage"
[[ -f "$FLAKE/flake.nix" && -f "$FLAKE/profile" ]] || exit 0

# Desktops have no online files.
idle() {
  local load f v ac_files=0 ac_online=0
  read -r load _ < /proc/loadavg
  awk -v l="$load" -v c="$(nproc)" 'BEGIN { exit !(l > c / 2) }' && return 1
  for f in /sys/class/power_supply/*/online; do
    [[ -r $f ]] || continue
    ac_files=1
    read -r v < "$f"; [[ $v == 1 ]] && ac_online=1
  done
  (( ac_files == 0 || ac_online == 1 ))
}

idle || exit 0

# Identical files hit the eval cache.
mkdir -p "$STAGE"
rm -rf "$STAGE/flake"
mkdir -p "$STAGE/flake"
cp "$FLAKE/flake.nix" "$FLAKE/local.nix" "$STAGE/flake/"
cp -r "$FLAKE/hardware" "$STAGE/flake/hardware"
# Older installs lack custom/.
if [[ -d "$FLAKE/custom" ]]; then cp -r "$FLAKE/custom" "$STAGE/flake/custom"; fi

# Same locking as nixlyos-update.
{ nixlyos-panel pin "$STAGE/flake" && (cd "$STAGE/flake" && nix flake lock); } >/dev/null 2>&1 || exit 0

# Big heap, fewer GC cycles.
export GC_INITIAL_HEAP_SIZE=2G

# Same file list as update.sh's tree_key.
key=$(cat "$STAGE/flake"/flake.nix "$STAGE/flake"/flake.lock "$STAGE/flake"/local.nix "$STAGE/flake"/custom/* "$STAGE/flake"/hardware/* 2>/dev/null | sha1sum | cut -d' ' -f1)
if [[ -f "$STAGE/key" && "$(<"$STAGE/key")" == "$key" && -e "$STAGE/result" ]]; then
  exit 0
fi

drv=$(nix eval --raw "$STAGE/flake#nixosConfigurations.nixlyos.config.system.build.toplevel.drvPath" 2>/dev/null) || exit 0
# Retried once the cache has it.
[[ -z "$(uncached "$drv")" ]] || exit 0

# The out-link is the GC root.
nix build --keep-going --out-link "$STAGE/result" "${CACHE_OPTS[@]}" "$drv^*" >/dev/null 2>&1 || exit 0

printf '%s\n' "$key" > "$STAGE/key"
