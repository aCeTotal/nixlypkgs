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

attrs=(
  linux-nixlyos
  linux-nixlyos-v3
  nvidia-nixlyos
  nvidia-nixlyos-persistenced
  nvidia-modules-nixlyos
  nvidia-modules-nixlyos-v3
  nixlytile
  nixlycc
  proton-nixlyos
  proton-nixlyos-generic
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

cd "$repo"
for a in "${attrs[@]}"; do
  if ! p=$(nix eval ".#$a.outPath" --raw 2>/dev/null); then
    printf '%-8s %4s  %-28s (lokal eval feilet)\n' FAILED - "$a"
    continue
  fi
  base=$(basename "$p")
  hash=${base%%-*}

  code=$(curl -s -o /dev/null -w '%{http_code}' "$cache/$hash.narinfo")
  if [ "$code" = 200 ]; then
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
