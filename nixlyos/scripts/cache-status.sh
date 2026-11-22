#!/usr/bin/env bash
# Which packages the cache serves.
set -euo pipefail

cache=https://cache.aceclan.no
repo=$(cd "$(dirname "$0")/../.." && pwd)

cd "$repo"

# One eval for every outPath.
paths=$(nix eval '.#packages.x86_64-linux' --json --apply '
  ps: builtins.mapAttrs (n: p:
    let t = builtins.tryEval (p.outPath or null);
    in if t.success then t.value else null)
    (builtins.removeAttrs ps [ "default" ])' 2>/dev/null
) || { echo "nix eval av flaken feilet" >&2; exit 1; }

declare -A path
while IFS=$'\t' read -r a p; do path[$a]=$p; done \
  < <(jq -r 'to_entries[] | "\(.key)\t\(.value)"' <<<"$paths")

declare -A code
while read -r h c; do code[$h]=$c; done < <(
  for a in "${!path[@]}"; do
    p=${path[$a]}; [ "$p" = null ] && continue
    b=${p##*/}; echo "${b%%-*}"
  done | sort -u | xargs -r -P 16 -I{} sh -c \
    'printf "%s %s\n" {} "$(curl -s -o /dev/null -w "%{http_code}" '"$cache"'/{}.narinfo)"'
)

for a in $(jq -r 'keys[]' <<<"$paths"); do
  p=${path[$a]}
  if [ "$p" = null ]; then
    printf '%-8s %-28s (lokal eval feilet)\n' FAILED "$a"
    continue
  fi
  base=${p##*/}
  if [ "${code[${base%%-*}]:-}" = 200 ]; then
    printf '%-8s %-28s %s\n' CACHED "$a" "$base"
  else
    printf '%-8s %-28s se byggestatus i panelet: %s\n' MISSING "$a" "$cache"
  fi
done
