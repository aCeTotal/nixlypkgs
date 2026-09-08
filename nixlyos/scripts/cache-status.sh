#!/usr/bin/env bash
# Status for nøkkel-pakkene fra denne flaken på cache.aceclan.no.
#
#   CACHED   100%      narinfo ligger på cachen
#   BUILDING  x% (…)   serveren bygger denne nå (x = medgått tid / forrige byggetid)
#   QUEUED             står i kø i pågående kjøring på serveren
#   FAILED             bygget feilet på serveren (eller lokal eval feilet)
#   WAITING            serveren har ikke plukket opp commiten ennå
#
# Live-progress krever /watcher/status.json på serveren (nixlycaching-watcheren).
set -euo pipefail

cache=https://cache.aceclan.no
repo=$(cd "$(dirname "$0")/../.." && pwd)

cd "$repo"

# Én eval for alle pakkers outPath (mye raskere enn en nix-prosess per attr)
paths=$(nix eval '.#packages.x86_64-linux' --json --apply '
  ps: builtins.mapAttrs (n: p:
    let t = builtins.tryEval (p.outPath or null);
    in if t.success then t.value else null)
    (builtins.removeAttrs ps [ "default" ])' 2>/dev/null
) || { echo "nix eval av flaken feilet" >&2; exit 1; }

declare -A path
while IFS=$'\t' read -r a p; do path[$a]=$p; done \
  < <(jq -r 'to_entries[] | "\(.key)\t\(.value)"' <<<"$paths")

# narinfo-sjekk mot cachen, parallelt
declare -A code
while read -r h c; do code[$h]=$c; done < <(
  for a in "${!path[@]}"; do
    p=${path[$a]}; [ "$p" = null ] && continue
    b=${p##*/}; echo "${b%%-*}"
  done | sort -u | xargs -r -P 16 -I{} sh -c \
    'printf "%s %s\n" {} "$(curl -s -o /dev/null -w "%{http_code}" '"$cache"'/{}.narinfo)"'
)

state=$(curl -sf "$cache/watcher/status.json" 2>/dev/null || echo '{}')
sv() { jq -r "$1 // empty" <<<"$state" 2>/dev/null || true; }

current=$(sv .current)
started=$(sv .current_started)
expected=$(sv .expected_seconds)
now=$(date +%s)

in_list() { # in_list <name> <jq-list-expr>
  jq -e --arg n "$1" "($2 // []) | index(\$n) != null" <<<"$state" >/dev/null 2>&1
}

fmt_min() { echo "$(( $1 / 60 ))m"; }

for a in $(jq -r 'keys[]' <<<"$paths"); do
  p=${path[$a]}
  if [ "$p" = null ]; then
    printf '%-8s %4s  %-28s (lokal eval feilet)\n' FAILED - "$a"
    continue
  fi
  base=${p##*/}
  hash=${base%%-*}

  if [ "${code[$hash]:-}" = 200 ]; then
    printf '%-8s %4s  %-28s %s\n' CACHED 100% "$a" "$base"
    continue
  fi

  if [ "$a" = "$current" ] && [ -n "$started" ]; then
    elapsed=$((now - started))
    if [ -n "$expected" ] && [ "${expected:-0}" -gt 0 ]; then
      pct=$((elapsed * 100 / expected))
      [ "$pct" -gt 99 ] && pct=99
      printf '%-8s %3d%%  %-28s %s av ~%s\n' BUILDING "$pct" "$a" "$(fmt_min $elapsed)" "$(fmt_min $expected)"
    else
      printf '%-8s %4s  %-28s bygget i %s\n' BUILDING - "$a" "$(fmt_min $elapsed)"
    fi
  elif in_list "$a" .queue; then
    printf '%-8s %4s  %-28s %s\n' QUEUED - "$a" "$base"
  elif in_list "$a" .failed; then
    printf '%-8s %4s  %-28s bygg feilet på server\n' FAILED - "$a"
  elif in_list "$a" .done; then
    printf '%-8s %4s  %-28s bygget, venter på cache\n' BUILT - "$a"
  else
    printf '%-8s %4s  %-28s %s\n' WAITING - "$a" "$base"
  fi
done
