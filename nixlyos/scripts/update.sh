#!/usr/bin/env bash
# NixlyOS update. The machine only tracks nixlypkgs: its flake.lock is the
# tested system pin, so `nix flake update nixlypkgs` pulls code AND every
# input revision exactly as pinned in nixlypkgs main.
# On any build failure the previous lock is restored, so the machine always
# lands on a generation that builds.
#
# Output contract: progress steps (henter, evaluerer, bygger/laster ned,
# aktiverer) and one "name  old > new" line per changed package — printed as
# each package finishes — reach the terminal. Everything else goes to the
# log. Errors and a required-reboot notice are the only exceptions. Without
# a tty only the version lines print, exactly as before.
set -euo pipefail

FLAKE="${NIXLYOS_DIR:-$HOME/.local/nixlyos}"
[[ -f "$FLAKE/flake.nix" ]] || { echo "error: missing $FLAKE/flake.nix" >&2; exit 1; }

# HTPC tracks ONLY the tested nixlypkgs pin: nixos-stable and home-manager
# stay exactly as locked in nixlypkgs' own flake.lock instead of moving to
# their branch heads. The couch box then updates to precisely the config
# revision pushed to nixlypkgs main, nothing else.
MODE=$(cat /etc/nixlyos-mode 2>/dev/null || echo desktop)

log="${XDG_STATE_HOME:-$HOME/.local/state}/nixlyos/update.log"
mkdir -p "$(dirname "$log")"
: > "$log"

# Eye candy only on a terminal; every escape collapses to "" otherwise, so
# the non-tty output stays plain and pipeable.
if [ -t 2 ]; then
  GRN=$'\033[32m' RED=$'\033[31m' CYN=$'\033[36m' DIM=$'\033[2m' RST=$'\033[0m'
else
  GRN='' RED='' CYN='' DIM='' RST=''
fi

say() { [ -t 2 ] && printf '%b\n' "$*" >&2 || :; }

# Animated status line for the blocking phases (lock, activation). The build
# phase animates itself from the nix event stream instead.
spin_pid=""
spin_start() {
  step_t=$SECONDS
  [ -t 2 ] || return 0
  (
    trap 'exit 0' TERM
    f='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏' i=0
    printf '\033[?25l' >&2
    while :; do
      printf '\033[2K\r%b' "${CYN}${f:i%10:1}${RST} ${DIM}$1${RST}" >&2
      sleep 0.12
      i=$((i+1))
    done
  ) &
  spin_pid=$!
}
spin_stop() { # $1: permanent line to leave behind ("" = just clear)
  [ -n "$spin_pid" ] && { kill "$spin_pid" 2>/dev/null || :; wait "$spin_pid" 2>/dev/null || :; spin_pid=""; }
  [ -t 2 ] || return 0
  printf '\033[2K\r\033[?25h' >&2
  if [ -n "${1:-}" ]; then printf '%b\n' "$1" >&2; fi
}
# ✓-line with elapsed time for the step started by spin_start.
tick() { spin_stop "${GRN}✓${RST} ${DIM}$1 ($((SECONDS - step_t))s)${RST}"; }

# Closure as "name<TAB>versions" lines: hash prefix stripped, versions of the
# same package collected, unversioned paths (config files etc.) dropped.
verlist() {
  nix path-info -r "$1" 2>>"$log" |
    awk '{ p=substr($0,45);
      if (!match(p, /-[0-9]/)) next
      print substr(p,1,RSTART-1) "\t" substr(p,RSTART+1)
    }' | LC_ALL=C sort -u |
    awk -F '\t' '
      $1 != prev { if (prev != "") print prev "\t" vs; prev=$1; vs=$2; next }
      { vs = vs ", " $2 }
      END { if (prev != "") print prev "\t" vs }'
}

# Ask for the password first, then keep the sudo timestamp warm so the final
# activation does not hit the five-minute timeout.
sudo -v
setsid bash -c 'while sudo -n true; do sleep 50; done' </dev/null >/dev/null 2>&1 &
sudo_keepalive=$!
tmp=$(mktemp -d -t nixlyos.XXXXXX)
trap 'kill -- -"$sudo_keepalive" 2>/dev/null; [ -n "$spin_pid" ] && kill "$spin_pid" 2>/dev/null; [ -n "${ver_pid:-}" ] && kill "$ver_pid" 2>/dev/null; [ -t 2 ] && printf "\033[?25h" >&2; rm -rf "$tmp"' EXIT

STAMP="${XDG_STATE_HOME:-$HOME/.local/state}/nixlyos/last-build"
mkdir -p "$(dirname "$STAMP")"

# The local tree is tiny, so its content plus the running system identify the
# last known result and let the eval be skipped entirely.
tree_key() { cat "$FLAKE"/flake.nix "$FLAKE"/flake.lock "$FLAKE"/local.nix "$FLAKE"/custom/* "$FLAKE"/hardware/* 2>/dev/null | sha1sum | cut -d' ' -f1; }

up_to_date() {
  printf '%s %s\n' "$(tree_key)" "$running" > "$STAMP"
  echo "Alt er oppdatert."
  exit 0
}

# Hardware detection and user config touch separate paths — run in parallel.
# user-config errors (reserved input name, broken inputs.nix) are user
# mistakes and go to the terminal.
spin_start "Validerer maskinvare og brukerkonfig …"
nixlyos-detect-hw "$FLAKE/hardware" >"$tmp/hw.log" 2>&1 &
hw_pid=$!
nixlyos-user-config "$FLAKE" >"$tmp/uc.log" 2>&1 || {
  spin_stop ""
  cat "$tmp/hw.log" "$tmp/uc.log" >>"$log" 2>/dev/null || :
  tail -5 "$tmp/uc.log" >&2
  exit 1
}
wait "$hw_pid"
cat "$tmp/hw.log" "$tmp/uc.log" >>"$log" 2>/dev/null || :
tick "Konfig validert"

# The old closure listing only reads the local store — overlap it with the
# network work below.
running=$(readlink -f /run/current-system)
verlist "$running" > "$tmp/old.tsv" &
ver_pid=$!

# Fast path — pacman-style "nothing to do" in a second or two: one parallel
# git ls-remote per moving input (nixlypkgs + the two branch-tracking ones).
# If no remote head moved and the local tree still matches the stamp, the
# whole lock/eval/build machinery is skipped. Any doubt (missing node,
# network error) falls through to the full path.
remote_moved() {
  local specs n=0 j moving=3
  # HTPC: only nixlypkgs moves, so only its head matters.
  [ "$MODE" = htpc ] && moving=1
  specs=$(jq -r --arg mode "$MODE" '
    .nodes | to_entries[]
    | select(.key == "nixlypkgs"
             or ($mode != "htpc" and (.key == "nixos-stable" or .key == "home-manager")))
    | select(.value.original.type? == "github")
    | "\(.value.original.owner)/\(.value.original.repo)\t\(.value.original.ref // "HEAD")\t\(.value.locked.rev)"
  ' "$FLAKE/flake.lock" 2>/dev/null) || return 0
  [ "$(printf '%s\n' "$specs" | grep -c .)" -eq "$moving" ] || return 0
  local repo ref rev pids=()
  while IFS=$'\t' read -r repo ref rev; do
    printf '%s' "$rev" > "$tmp/want.$n"
    { r=$(git ls-remote "https://github.com/$repo" \
            "$([ "$ref" = HEAD ] && echo HEAD || echo "refs/heads/$ref")" \
            2>/dev/null | head -1 | cut -f1) || :
      printf '%s' "$r" > "$tmp/head.$n"
    } &
    pids+=($!)
    n=$((n+1))
  done <<< "$specs"
  wait "${pids[@]}" 2>/dev/null || :
  for (( j=0; j<n; j++ )); do
    [ -s "$tmp/head.$j" ] || return 0
    [ "$(cat "$tmp/head.$j")" = "$(cat "$tmp/want.$j")" ] || return 0
  done
  return 1
}

skey="" ssys=""
if [ -s "$STAMP" ]; then read -r skey ssys < "$STAMP"; fi
if [ -s "$FLAKE/flake.lock" ] && [ "$skey" = "$(tree_key)" ] && [ "$ssys" = "$running" ]; then
  spin_start "Sjekker etter oppdateringer …"
  if ! remote_moved; then
    tick "Ingen nye versjoner"
    up_to_date
  fi
  tick "Oppdateringer funnet"
fi

lockbak="$tmp/flake.lock"
cp "$FLAKE/flake.lock" "$lockbak" 2>/dev/null || : > "$lockbak"
spin_start "Henter siste versjoner …"
# Re-lock from scratch instead of `nix flake update nixlypkgs`: update
# re-resolves the whole subtree to branch heads, while a fresh lock inherits
# every nested rev from nixlypkgs' own tested flake.lock. On top of that,
# nixpkgs stable (and home-manager, which tracks the same release) always
# moves to the newest head of its branch, so stable security updates flow
# without a maintainer bump. Kernel/chaotic, unstable and our own packages
# stay exactly as pinned. A failed build still rolls back the whole lock.
rm -f "$FLAKE/flake.lock"
# cd instead of --flake: the pinned nix (stable nixpkgs) still uses the old
# CLI where flake lock/update only operate on the current directory.
# --refresh: skip the 1h github fetcher cache, or a push made minutes ago
# resolves to the previous rev and the new flake.nix meets old code.
if ! (cd "$FLAKE" && nix flake lock --refresh &&
      { [ "$MODE" = htpc ] ||
        nix flake update --refresh nixlypkgs/nixos-stable nixlypkgs/home-manager; }) >>"$log" 2>&1; then
  spin_stop ""
  cp "$lockbak" "$FLAKE/flake.lock"
  tail -20 "$log" >&2
  exit 1
fi
tick "Siste versjoner hentet"

[ "$skey" = "$(tree_key)" ] && [ "$ssys" = "$running" ] && up_to_date

ATTR="$FLAKE#nixosConfigurations.nixlyos.config.system.build.toplevel"

# Live progress: one status line (spinner + phase/counts) plus one line per
# active build/download, redrawn in place at the bottom. As each package
# finishes, a permanent "name  old > new" line is printed above the footer
# and its name recorded in $tmp/printed so print_diff does not repeat it.
# Reads nix's internal-json activity stream. Skipped when stderr is no tty.
render_progress() {
  if [ ! -t 2 ]; then cat >/dev/null; return 0; fi
  jq --unbuffered -rR '
    (try (ltrimstr("@nix ") | fromjson) catch empty) |
    if .action == "start" and (.type == 105 or .type == 108) then
      "S\t\(.id)\t\(if .type == 105 then "B" else "D" end)\t\(.fields[0] // .text // "")"
    elif .action == "stop" then "E\t\(.id)"
    else empty end
  ' | {
    declare -A label kind pname pver oldv printed
    order=(); shown=0; phase='eval'
    frames='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'; fr=0
    cols=$(tput cols 2>/dev/null || echo 120)
    while IFS=$'\t' read -r n v; do oldv[$n]=$v; done < "$tmp/old.tsv"
    printf '\033[?25l' >&2
    trap 'printf "\033[?25h" >&2' EXIT

    header() {
      local nb=0 nd=0 id
      for id in "${order[@]}"; do
        [[ -n ${label[$id]:-} ]] || continue
        if [[ ${kind[$id]} == B ]]; then nb=$((nb+1)); else nd=$((nd+1)); fi
      done
      local s="${CYN}${frames:fr:1}${RST} "
      if [[ $phase == eval ]]; then
        s+="${DIM}Evaluerer systemet …${RST}"
      else
        local p=""
        (( nb > 0 )) && p="bygger ${nb}"
        (( nd > 0 )) && p+="${p:+ ${DIM}·${RST} }laster ned ${nd}"
        [[ -n $p ]] || p="${DIM}venter …${RST}"
        s+=$p
      fi
      printf '%b' "$s"
    }

    redraw() {
      (( shown > 0 )) && printf '\033[%dA' "$shown" >&2
      local lines=1 id
      printf '\033[2K%b\n' "$(header)" >&2
      for id in "${order[@]}"; do
        [[ -n ${label[$id]:-} ]] || continue
        printf '\033[2K  %b\n' "${label[$id]}" >&2
        lines=$((lines+1))
      done
      local extra=$((shown - lines)) i
      if (( extra > 0 )); then
        for (( i=0; i<extra; i++ )); do printf '\033[2K\n' >&2; done
        printf '\033[%dA' "$extra" >&2
      fi
      shown=$lines
    }

    wipe() {
      (( shown > 0 )) || return 0
      printf '\033[%dA' "$shown" >&2
      local i
      for (( i=0; i<shown; i++ )); do printf '\033[2K\033[B' >&2; done
      printf '\033[%dA' "$shown" >&2
      shown=0
    }

    perm() { wipe; printf '\033[2K%b\n' "$1" >&2; redraw; }

    while :; do
      if IFS=$'\t' read -t 0.15 -r ev id k path; then
        case $ev in
          S)
            if [[ $phase == eval ]]; then
              phase=build
              perm "${GRN}✓${RST} ${DIM}Systemet evaluert (${SECONDS}s)${RST}"
            fi
            # /nix/store/<hash>-name(.drv) -> name
            p=${path##*/}; p=${p:33}; p=${p%.drv}
            [[ -n $p ]] || continue
            # First "-<digit>" splits package name from version.
            nm=""; vr=""; pre=""; rest=$p
            while [[ $rest == *-* ]]; do
              seg=${rest%%-*}; rest=${rest#*-}; pre+=$seg
              if [[ $rest == [0-9]* ]]; then nm=$pre; vr=$rest; break; fi
              pre+=-
            done
            verb=bygger; [[ $k == D ]] && verb='laster ned'
            label[$id]="${DIM}${verb}${RST} ${p:0:cols-16}"
            kind[$id]=$k
            pname[$id]=$nm
            pver[$id]=$vr
            order+=("$id")
            redraw
            ;;
          E)
            if [[ -n ${label[$id]:-} ]]; then
              nm=${pname[$id]}; vr=${pver[$id]}
              unset "label[$id]"
              if [[ -n $nm && -z ${printed[$nm]:-} ]]; then
                o=${oldv[$nm]:-}
                if [[ -z $o ]]; then
                  printed[$nm]=1; echo "$nm" >> "$tmp/printed"
                  perm "  ${GRN}+${RST} $nm ${GRN}$vr${RST}"
                elif [[ $o != "$vr" ]]; then
                  printed[$nm]=1; echo "$nm" >> "$tmp/printed"
                  perm "  $nm  ${DIM}${o}${RST} > ${GRN}${vr}${RST}"
                else
                  redraw
                fi
              else
                redraw
              fi
            fi
            ;;
        esac
      else
        rc=$?
        if (( rc > 128 )); then fr=$(( (fr+1) % 10 )); redraw; continue; fi
        break
      fi
    done
    wipe
  }
}

# Fast path: the background stager (nixlyos-stage) may already have built
# exactly this system. Its key is the sha1 of the same file list as tree_key,
# so a match proves the staged result was built from identical inputs.
STAGEDIR="${XDG_STATE_HOME:-$HOME/.local/state}/nixlyos/stage"
staged_sys() {
  [[ -f "$STAGEDIR/key" && -e "$STAGEDIR/result" ]] || return 1
  [[ "$(<"$STAGEDIR/key")" == "$(tree_key)" ]] || return 1
  readlink -f "$STAGEDIR/result"
}

# Full-throttle build: every core, one build slot per core, wide substitution
# fan-out, and fast failover past unreachable caches. The conservative
# max-jobs/cores in nix.nix stay in place for background builds; the override
# applies to this invocation only.
build_sys() {
  local rc=0
  if staged_sys > "$tmp/out"; then
    say "${GRN}✓${RST} ${DIM}Ferdig bygget i bakgrunnen — gjenbruker resultatet${RST}"
    return 0
  fi
  # Pre-sized Boehm heap: cold evals run far fewer GC cycles.
  export GC_INITIAL_HEAP_SIZE=4G
  # The cache lines also live in nix.nix, but the running generation's
  # nix.conf may predate them; injecting here breaks that chicken-and-egg.
  # The user is in trusted-users, so the daemon accepts both options.
  nix build --no-link --print-out-paths --keep-going "$ATTR" \
    --max-jobs "$(nproc)" --cores 0 \
    --option extra-substituters 'https://cache.aceclan.no?priority=5' \
    --option extra-trusted-public-keys cache.aceclan.no-1:qfGAXabgsofKSAqId9sqqbPlQic4l7gOGeWPrqUg3ak= \
    --option max-substitution-jobs 128 \
    --option http-connections 128 \
    --option connect-timeout 3 \
    --option download-buffer-size 536870912 \
    --option fallback true \
    --log-format internal-json \
    >"$tmp/out" 2> >(tee -a "$log" | render_progress) || rc=$?
  psub=$!
  wait "$psub" 2>/dev/null || true
  return "$rc"
}

# switch-to-configuration inside a transient unit, like nixos-rebuild does, so
# activation survives if it restarts the very session this script runs in.
activate() { # switch|boot
  # shellcheck disable=SC2024  # the log is user-owned by design
  sudo systemd-run --collect --no-ask-password --pipe --quiet --wait \
    --service-type=exec --unit="nixlyos-$1-$$" \
    "$sys/bin/switch-to-configuration" "$1" >>"$log" 2>&1
}

# One line per changed program, old > new. Packages already printed live by
# render_progress (recorded in $tmp/printed) are skipped.
print_diff() {
  verlist "$sys" > "$tmp/new.tsv"
  LC_ALL=C join -t "$(printf '\t')" -a1 -a2 -e '-' -o 0,1.2,2.2 "$tmp/old.tsv" "$tmp/new.tsv" |
    awk -F '\t' -v pf="$tmp/printed" -v G="$GRN" -v R="$RED" -v D="$DIM" -v N="$RST" '
      BEGIN { while ((getline l < pf) > 0) seen[l] = 1 }
      $2 == $3 || ($1 in seen) { next }
      {
        if ($2 == "-")      printf "  %s+%s %s %s%s%s\n", G, N, $1, G, $3, N
        else if ($3 == "-") printf "  %s-%s %s %s%s%s  %sfjernet%s\n", R, N, $1, D, $2, N, R, N
        else                printf "  %s  %s%s%s > %s%s%s\n", $1, D, $2, N, G, $3, N
      }'
}

# 0 activated, 2 built but only set for next boot, 3 nothing new, 1 failed.
rebuild() {
  wait "$ver_pid" 2>/dev/null || :
  : > "$tmp/printed"
  build_sys || return 1
  sys=$(<"$tmp/out")
  [ "$sys" = "$running" ] && return 3
  # shellcheck disable=SC2024
  sudo nix-env -p /nix/var/nix/profiles/system --set "$sys" >>"$log" 2>&1 || return 1
  print_diff
  spin_start "Aktiverer nytt system …"
  if activate switch; then tick "Aktivert"; return 0; fi
  spin_stop ""
  activate boot && return 2
  return 1
}

rebuild && rc=0 || rc=$?
(( rc == 3 )) && up_to_date

# The whole update is one pin, so the rollback is one step: the previous lock,
# which is known to build.
if (( rc == 1 )) && ! cmp -s "$lockbak" "$FLAKE/flake.lock"; then
  cp "$lockbak" "$FLAKE/flake.lock"
  rebuild && rc=0 || rc=$?
  (( rc == 3 )) && rc=0
fi

case $rc in
  0|2) ;;
  *)
    # The log is an internal-json stream during the build; surface the human
    # messages, or the raw tail if none parse.
    msgs=$(jq -rR 'try (ltrimstr("@nix ") | fromjson) catch empty | select(.action == "msg") | .msg' "$log" 2>/dev/null | tail -30)
    if [ -n "$msgs" ]; then printf '%s\n' "$msgs" >&2; else tail -30 "$log" >&2; fi
    echo "error: oppdatering feilet (full logg: $log)" >&2
    exit 1
    ;;
esac

printf '%s %s\n' "$(tree_key)" "$(readlink -f /run/current-system)" > "$STAMP"

(( rc == 0 )) && say "${GRN}✓${RST} Oppdatering fullført ${DIM}(${SECONDS}s totalt)${RST}"

# Silent except when action is needed: kernel/initrd/nvidia only take effect
# after a reboot, and hiding that would be unsafe.
needs_reboot=""
for part in kernel initrd kernel-modules; do
  [ "$(readlink -f "/run/booted-system/$part" 2>/dev/null)" = \
    "$(readlink -f "/run/current-system/$part" 2>/dev/null)" ] || needs_reboot=1
done
nv_running=$(awk '/NVRM version/ {print $8}' /proc/driver/nvidia/version 2>/dev/null || true)
nv_new=$(readlink -f /run/current-system/kernel-modules/lib/modules/*/kernel/drivers/video/nvidia.ko* 2>/dev/null |
  grep -oP 'nvidia-kernel-modules-\K[0-9.]+' | head -1 || true)
if { [ -n "$nv_running" ] && [ -n "$nv_new" ] && [ "$nv_running" != "$nv_new" ]; } || [ -n "$needs_reboot" ]; then
  echo "Omstart kreves."
fi
(( rc == 2 )) && echo "Aktivering feilet — ny versjon gjelder fra neste boot." >&2
exit 0
