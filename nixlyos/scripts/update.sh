#!/usr/bin/env bash
# NixlyOS update. The machine only tracks nixlypkgs: its flake.lock is the
# tested system pin, so `nix flake update nixlypkgs` pulls code AND every
# input revision exactly as pinned in nixlypkgs main.
# On any build failure the previous lock is restored, so the machine always
# lands on a generation that builds.
#
# Output contract: only version transitions ("name  old > new") reach the
# terminal. Everything else goes to the log. Errors and a required-reboot
# notice are the only exceptions.
set -euo pipefail

FLAKE="${NIXLYOS_DIR:-$HOME/.local/nixlyos}"
[[ -f "$FLAKE/flake.nix" ]] || { echo "error: missing $FLAKE/flake.nix" >&2; exit 1; }

log="${XDG_STATE_HOME:-$HOME/.local/state}/nixlyos/update.log"
mkdir -p "$(dirname "$log")"
: > "$log"

# Ask for the password first, then keep the sudo timestamp warm so the final
# activation does not hit the five-minute timeout.
sudo -v
setsid bash -c 'while sudo -n true; do sleep 50; done' </dev/null >/dev/null 2>&1 &
sudo_keepalive=$!
tmp=$(mktemp -d -t nixlyos.XXXXXX)
trap 'kill -- -"$sudo_keepalive" 2>/dev/null; rm -rf "$tmp"' EXIT

nixlyos-detect-hw "$FLAKE/hardware" >>"$log" 2>&1
# Seed/refresh custom/{inputs,modules}.nix and the user-inputs flake block.
# Must run before locking so new inputs get resolved. Its errors (reserved
# input name, broken inputs.nix) are user mistakes and go to the terminal.
nixlyos-user-config "$FLAKE" >>"$log" 2>&1 || { tail -5 "$log" >&2; exit 1; }

lockbak="$tmp/flake.lock"
cp "$FLAKE/flake.lock" "$lockbak" 2>/dev/null || : > "$lockbak"
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
      nix flake update --refresh nixlypkgs/nixos-stable nixlypkgs/home-manager) >>"$log" 2>&1; then
  cp "$lockbak" "$FLAKE/flake.lock"
  tail -20 "$log" >&2
  exit 1
fi

STAMP="${XDG_STATE_HOME:-$HOME/.local/state}/nixlyos/last-build"
mkdir -p "$(dirname "$STAMP")"

# The local tree is tiny, so its content plus the running system identify the
# last known result and let the eval be skipped entirely.
tree_key() { cat "$FLAKE"/flake.nix "$FLAKE"/flake.lock "$FLAKE"/local.nix "$FLAKE"/custom/* "$FLAKE"/hardware/* 2>/dev/null | sha1sum | cut -d' ' -f1; }

key=$(tree_key)
running=$(readlink -f /run/current-system)

up_to_date() {
  printf '%s %s\n' "$key" "$running" > "$STAMP"
  echo "Alt er oppdatert."
  exit 0
}

skey="" ssys=""
if [ -s "$STAMP" ]; then read -r skey ssys < "$STAMP"; fi
[ "$skey" = "$key" ] && [ "$ssys" = "$running" ] && up_to_date

ATTR="$FLAKE#nixosConfigurations.nixlyos.config.system.build.toplevel"

# Live footer: everything currently building or downloading, one line each,
# redrawn in place at the bottom. Reads nix's internal-json activity stream.
# Skipped when stderr is not a terminal.
render_footer() {
  if [ ! -t 2 ]; then cat >/dev/null; return 0; fi
  jq --unbuffered -rR '
    (try (ltrimstr("@nix ") | fromjson) catch empty) |
    if .action == "start" and (.type == 105 or .type == 108) then
      "S\t\(.id)\t\(if .type == 105 then "bygger" else "installerer" end)\t\(.fields[0] // .text // "")"
    elif .action == "stop" then "E\t\(.id)"
    else empty end
  ' | {
    declare -A label; order=(); shown=0
    redraw() {
      (( shown > 0 )) && printf '\033[%dA' "$shown" >&2
      local count=0 id
      for id in "${order[@]}"; do
        [[ -n ${label[$id]:-} ]] || continue
        printf '\033[2K%s\n' "${label[$id]}" >&2
        (( ++count ))
      done
      local extra=$(( shown - count )) i
      for (( i=0; i<extra; i++ )); do printf '\033[2K\n' >&2; done
      (( extra > 0 )) && printf '\033[%dA' "$extra" >&2
      shown=$count
    }
    while IFS=$'\t' read -r ev id verb path; do
      if [[ $ev == S ]]; then
        # /nix/store/<hash>-name(.drv) -> name
        p=${path##*/}; p=${p:33}; p=${p%.drv}
        [[ -n $p ]] || continue
        label[$id]="$verb $p"
        order+=("$id")
      else
        unset "label[$id]"
      fi
      redraw
    done
    # Leave a clean prompt line: wipe the footer.
    (( shown > 0 )) && { printf '\033[%dA' "$shown" >&2; for (( i=0; i<shown; i++ )); do printf '\033[2K\n' >&2; done; printf '\033[%dA' "$shown" >&2; }
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
    return 0
  fi
  # Pre-sized Boehm heap: cold evals run far fewer GC cycles.
  export GC_INITIAL_HEAP_SIZE=4G
  # The cache lines also live in nix.nix, but the running generation's
  # nix.conf may predate them; injecting here breaks that chicken-and-egg.
  # The user is in trusted-users, so the daemon accepts both options.
  nix build --no-link --print-out-paths --keep-going "$ATTR" \
    --max-jobs "$(nproc)" --cores 0 \
    --option extra-substituters https://cache.aceclan.no \
    --option extra-trusted-public-keys cache.aceclan.no-1:qfGAXabgsofKSAqId9sqqbPlQic4l7gOGeWPrqUg3ak= \
    --option max-substitution-jobs 128 \
    --option http-connections 128 \
    --option connect-timeout 3 \
    --option fallback true \
    --log-format internal-json \
    >"$tmp/out" 2> >(tee -a "$log" | render_footer) || rc=$?
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

# The only regular output: one line per changed program, old > new.
print_diff() {
  verlist "$running" > "$tmp/old.tsv"
  verlist "$sys" > "$tmp/new.tsv"
  LC_ALL=C join -t "$(printf '\t')" -a1 -a2 -e '-' -o 0,1.2,2.2 "$tmp/old.tsv" "$tmp/new.tsv" |
    awk -F '\t' '$2 != $3 {
      if ($2 == "-")      printf "%s  + %s\n", $1, $3
      else if ($3 == "-") printf "%s  - %s\n", $1, $2
      else                printf "%s  %s > %s\n", $1, $2, $3
    }'
}

# 0 activated, 2 built but only set for next boot, 3 nothing new, 1 failed.
rebuild() {
  build_sys || return 1
  sys=$(<"$tmp/out")
  [ "$sys" = "$running" ] && return 3
  # shellcheck disable=SC2024
  sudo nix-env -p /nix/var/nix/profiles/system --set "$sys" >>"$log" 2>&1 || return 1
  print_diff
  activate switch && return 0
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
