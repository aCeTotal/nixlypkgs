#!/usr/bin/env bash
# GC-roots every flake in ~/git.
set -euo pipefail
shopt -s nullglob

PROJECTS="$HOME/git"
ROOTS="${XDG_STATE_HOME:-$HOME/.local/state}/nixly-project-roots"

# Chained: errexit is off under `if`.
root_project() {
  local dir=$1 out=$2 archive inputs
  archive=$(nix flake archive --json "$dir") &&
    mapfile -t inputs < <(jq -r '.inputs | .. | .path? // empty' <<<"$archive") &&
    nix-store --add-root "$out/input" --realise "${inputs[@]}" >/dev/null &&
    nix print-dev-env --profile "$out/shell" "$dir" >/dev/null &&
    nix build --out-link "$out/run" "$dir"
}

mkdir -p "$ROOTS"
# Roots are tracked by path, so build in place.
for flake in "$PROJECTS"/*/flake.nix; do
  dir=${flake%/flake.nix}
  name=${dir##*/}
  out="$ROOTS/$name"
  backup="$ROOTS/.$name"
  rm -rf "$backup"
  mkdir -p "$out"
  mv "$out" "$backup"
  mkdir "$out"
  if root_project "$dir" "$out"; then
    rm -rf "$backup"
    continue
  fi
  echo "project-roots: $name failed, keeping previous roots" >&2
  rm -rf "$out"
  mv "$backup" "$out"
done

for kept in "$ROOTS"/*; do
  [[ -f "$PROJECTS/${kept##*/}/flake.nix" ]] || rm -rf "$kept"
done
