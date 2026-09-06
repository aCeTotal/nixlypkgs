#!/usr/bin/env bash
# Maintainer-side input bump, run in a nixlypkgs checkout on the testing
# branch. Bumps the stable channel when a new NixOS release exists (both the
# nixpkgs branch and the matching home-manager branch must exist), then
# updates every flake input. The result is committed, tested on a machine on
# the testing channel, and only then merged to release.
set -euo pipefail

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
FLAKE="$REPO/flake.nix"

cur=$(grep -oP 'nixos-stable\.url = "github:NixOS/nixpkgs/nixos-\K[0-9]{2}\.[0-9]{2}' "$FLAKE")

# 25.11 -> 26.05 -> 26.11 -> 27.05 ...
next_ver() {
  local y=${1%%.*} m=${1##*.}
  if [ "$m" = "05" ]; then echo "$y.11"; else printf '%02d.05\n' $((10#$y + 1)); fi
}

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
git ls-remote --heads https://github.com/NixOS/nixpkgs 'nixos-[0-9]*' >"$tmp/np"
git ls-remote --heads https://github.com/nix-community/home-manager 'release-*' >"$tmp/hm"

new=$cur
while cand=$(next_ver "$new") &&
      grep -q "refs/heads/nixos-$cand\$" "$tmp/np" &&
      grep -q "refs/heads/release-$cand\$" "$tmp/hm"; do
  new=$cand
done
if [ "$new" != "$cur" ]; then
  echo "bumping stable channel $cur -> $new"
  sed -i "s|nixpkgs/nixos-$cur|nixpkgs/nixos-$new|; s|home-manager/release-$cur|home-manager/release-$new|" "$FLAKE"
else
  echo "stable channel: $cur (current)"
fi

nix flake update --flake "$REPO"
echo "done — build-test a machine on the testing channel before merging to release"
