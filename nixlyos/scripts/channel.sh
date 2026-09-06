#!/usr/bin/env bash
# Switch the machine between the release and testing channel of nixlypkgs.
# The channel is just the branch in the nixlypkgs flake input; nixlycc calls
# this with an argument, humans get the same interface.
#   nixlyos-channel            show current channel
#   nixlyos-channel release    tested and safe (default)
#   nixlyos-channel testing    new changes before promotion
set -euo pipefail

FLAKE="${NIXLYOS_DIR:-$HOME/.local/nixlyos}/flake.nix"
[[ -f $FLAKE ]] || { echo "error: missing $FLAKE" >&2; exit 1; }

current() {
  grep -oP 'nixlypkgs\.url = "github:aCeTotal/nixlypkgs/\K[^"]+' "$FLAKE" || echo "dev"
}

case "${1:-}" in
  ""|status)
    current
    ;;
  release|testing)
    cur=$(current)
    if [[ $cur == "$1" ]]; then
      echo "already on $1"
      exit 0
    fi
    if [[ $cur == dev ]]; then
      echo "error: flake input is a dev checkout, not a channel — edit $FLAKE manually" >&2
      exit 1
    fi
    sed -i "s|nixlypkgs\.url = \"github:aCeTotal/nixlypkgs/$cur\"|nixlypkgs.url = \"github:aCeTotal/nixlypkgs/$1\"|" "$FLAKE"
    echo "channel: $cur -> $1"
    echo "run nixlyos-update to switch the system"
    ;;
  *)
    echo "usage: nixlyos-channel [release|testing|status]" >&2
    exit 1
    ;;
esac
