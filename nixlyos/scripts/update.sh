# NixlyOS update: the panel's release, from cache only.
set -euo pipefail

FLAKE="${NIXLYOS_DIR:-$HOME/.local/nixlyos}"
[[ -f "$FLAKE/flake.nix" ]] || { echo "error: missing $FLAKE/flake.nix" >&2; exit 1; }

STATE="${XDG_STATE_HOME:-$HOME/.local/state}/nixlyos"
STAMP="$STATE/last-build"
STAGEDIR="$STATE/stage"
EVAL_TIME="$STATE/eval-us"
CONFIG="$FLAKE#nixosConfigurations.nixlyos.config"
MIN_FREE_KIB=$((50 * 1024 * 1024))
KEEP_GENERATIONS=3d
PASSWORD_TRIES=3
MAX_ERRORS=3
log="$STATE/update.log"
mkdir -p "$STATE"
: > "$log"

tmp=$(mktemp -d -t nixlyos.XXXXXX)
keepalive=""
eval_pid=""
trap 'spin_stop; [ -z "$keepalive" ] || kill "$keepalive" 2>/dev/null || :; [ -z "$eval_pid" ] || kill "$eval_pid" 2>/dev/null || :; (( tty )) && printf "\033[?25h\033[?7h\n" >&2; rm -rf "$tmp"' EXIT

# Same file list as stage.sh.
tree_key() {
  cat "$FLAKE"/flake.nix "$FLAKE"/flake.lock "$FLAKE"/local.nix \
    "$FLAKE"/custom/* "$FLAKE"/hardware/* 2>/dev/null | sha1sum | cut -d' ' -f1
}

up_to_date() {
  printf '%s %s\n' "$(tree_key)" "$running" > "$STAMP"
  step_done "Alt er oppdatert" $(( ${EPOCHREALTIME/[.,]/} - started ))
  (( tty )) || echo "Alt er oppdatert."
  exit 0
}

validate_config() {
  spin_start "Sjekker konfigurasjon"
  nixlyos-detect-hw "$FLAKE/hardware" >"$tmp/hw.log" 2>&1 &
  local hw=$!
  if ! nixlyos-user-config "$FLAKE" >"$tmp/uc.log" 2>&1; then
    spin_stop
    tail -5 "$tmp/uc.log" | error_block "Ugyldig konfigurasjon"
    exit 1
  fi
  wait "$hw"
  cat "$tmp/hw.log" "$tmp/uc.log" >>"$log"
  tick "Konfigurasjon sjekket"
}

stamp_matches() {
  local key="" built=""
  [ -s "$STAMP" ] && read -r key built < "$STAMP"
  [ -s "$FLAKE/flake.lock" ] && [ "$key" = "$(tree_key)" ] && [ "$built" = "$running" ]
}

check_remote() {
  stamp_matches || return 0
  spin_start "Ser etter oppdateringer"
  newer_release && { tick "Nye versjoner tilgjengelig"; return 0; }
  spin_stop
  up_to_date
}

# Own prompt, erased once accepted.
ask_password() {
  local pw prompt="Passord for $USER" try
  for (( try = 0; try < PASSWORD_TRIES; try++ )); do
    printf '\r  %s?%s %s: \033[?25h' "$CYN" "$RST" "$prompt" >&2
    IFS= read -rs pw
    printf '\r\033[2K\033[?25l' >&2
    printf '%s\n' "$pw" | sudo -S -p '' -v 2>/dev/null && return 0
    prompt="Feil passord, prøv igjen"
  done
  error_block "Fikk ikke tilgang med sudo" </dev/null
  exit 1
}

# Password once, warm per tty.
sudo_start() {
  if ! sudo -n true 2>/dev/null; then
    if (( tty )); then ask_password; else sudo -v; fi
  fi
  ( while sudo -n -v 2>/dev/null; do nap 50; done ) </dev/null >/dev/null 2>&1 &
  keepalive=$!
}

free_disk() {
  (( $(df --output=avail /nix | tail -1) < MIN_FREE_KIB )) || return 0
  spin_start "Rydder gamle generasjoner"
  { sudo nix-env -p /nix/var/nix/profiles/system --delete-generations "$KEEP_GENERATIONS"; } >>"$log" 2>&1
  nix-collect-garbage --delete-older-than "$KEEP_GENERATIONS" >>"$log" 2>&1 || :
  tick "Diskplass frigjort"
}

staged_sys() {
  [[ -f "$STAGEDIR/key" && -e "$STAGEDIR/result" ]] || return 1
  [[ "$(<"$STAGEDIR/key")" == "$(tree_key)" ]] || return 1
  readlink -f "$STAGEDIR/result"
}

# Background parallel eval to $tmp/drv.
eval_start() {
  eval_t=${EPOCHREALTIME/[.,]/}
  (
    trap 'kill $! 2>/dev/null || :' EXIT
    GC_INITIAL_HEAP_SIZE=4G NIX_SENTRY_ENDPOINT='' "$EVAL_NIX" eval --raw --no-eval-cache "$CONFIG" \
      --apply "$(<"$EVAL_APPLY")" \
      --option eval-cores 0 \
      --extra-experimental-features parallel-eval \
      --log-format internal-json \
      </dev/null >"$tmp/drv" 2> >(grep -v '^@nix {"action":"\(start\|stop\|result\)"' >>"$log") &
    rc=0
    wait $! || rc=$?
    printf '%s\n' "${EPOCHREALTIME/[.,]/}" > "$tmp/eval-end"
    exit "$rc"
  ) &
  eval_pid=$!
}

# Waits with bar, records time.
eval_wait() {
  local rc=0 took
  render_eval "$eval_pid" "$eval_t" "$EVAL_TIME"
  wait "$eval_pid" || rc=$?
  eval_pid=""
  (( rc == 0 )) || return "$rc"
  took=$(( $(<"$tmp/eval-end") - eval_t ))
  printf '%s\n' "$took" > "$EVAL_TIME"
  step_done "System evaluert" "$took"
}

# Missing cache entries abort untouched.
cache_check() {
  local missing
  spin_start "Sjekker at alt finnes i cachen"
  missing=$(uncached "$1")
  if [ -n "$missing" ]; then
    spin_stop
    cp "$tmp/old.lock" "$FLAKE/flake.lock"
    { head -10 <<< "$missing"; echo "Panelet har ikke bygget dette ennå, prøv igjen senere."; } | error_block "Ikke i cachen ennå"
    exit 1
  fi
  tick "Alt finnes i cachen"
}

# Every core, wide substitution fan-out.
build_sys() {
  if [ -n "$staged" ]; then
    printf '%s\n' "$staged" > "$tmp/out"
    step_done "Ferdig bygget i bakgrunnen"
    return 0
  fi
  eval_wait || return
  cache_check "$(<"$tmp/drv")"
  local rc=0
  # Braces put view pid in $!.
  {
    nix build --no-link --print-out-paths --keep-going "$(<"$tmp/drv")^*" \
      --max-jobs "$(nproc)" --cores 0 \
      "${CACHE_OPTS[@]}" \
      --option max-substitution-jobs 128 \
      --option http-connections 128 \
      --option download-buffer-size 536870912 \
      --log-format internal-json \
      >"$tmp/out"
  } 2> >(LC_ALL=C awk -f "$PROGRESS_AWK" 2>>"$log" | render_progress) || rc=$?
  wait $! 2>/dev/null || :
  return "$rc"
}

# Root causes, deduplicated.
nix_errors() {
  local msgs
  msgs=$(jq -nrR --argjson keep "$MAX_ERRORS" '
    [inputs | try (ltrimstr("@nix ") | fromjson) catch empty
     | select(.action == "msg" and .level == 0) | .msg
     | select(test("Reason: (\u001b\\[[0-9;]*m)?[0-9]+ dependenc") | not)]
    | reduce .[] as $m ([]; if index([$m]) then . else . + [$m] end)
    | .[-$keep:][]' "$log")
  if [ -n "$msgs" ]; then printf '%s\n' "$msgs"; else tail -30 "$log"; fi
}

fail() {
  cp "$tmp/old.lock" "$FLAKE/flake.lock"
  { nix_errors; echo "${DIM}Logg: ${log/#"$HOME"/\~}${RST}"; } | error_block "Oppdatering feilet"
  exit 1
}

# Activation in its own unit survives session restarts.
activate() {
  { sudo systemd-run --collect --no-ask-password --pipe --quiet --wait \
    --service-type=exec --unit="nixlyos-$1-$$" \
    "$sys/bin/switch-to-configuration" "$1"; } >>"$log" 2>&1
}

needs_reboot() {
  local part nv_running nv_new
  for part in kernel initrd kernel-modules; do
    [ "$(readlink -f "/run/booted-system/$part")" = "$(readlink -f "/run/current-system/$part")" ] || return 0
  done
  nv_running=$(awk '/NVRM version/ {print $8}' /proc/driver/nvidia/version 2>/dev/null || :)
  nv_new=$(readlink -f /run/current-system/kernel-modules/lib/modules/*/kernel/drivers/video/nvidia.ko* 2>/dev/null |
    grep -oP 'nvidia-kernel-modules-\K[0-9.]+' | head -1 || :)
  [ -n "$nv_running" ] && [ -n "$nv_new" ] && [ "$nv_running" != "$nv_new" ]
}

started=${EPOCHREALTIME/[.,]/}
header
validate_config
panel_join
running=$(readlink -f /run/current-system)
check_remote
nix path-info -r "$running" > "$tmp/old.paths" &
paths_pid=$!
lock_panel
stamp_matches && up_to_date
sudo_start
free_disk
staged=$(staged_sys) || eval_start
wait "$paths_pid"

build_sys || fail
sys=$(<"$tmp/out")
[ "$sys" = "$running" ] && up_to_date

nix path-info -r "$sys" > "$tmp/new.paths"
print_changes "$tmp" "$running" "$sys"
{ sudo nix-env -p /nix/var/nix/profiles/system --set "$sys"; } >>"$log" 2>&1
spin_start "Aktiverer"
booted_only=0
if activate switch; then
  tick "Aktivert"
else
  spin_stop
  activate boot || fail
  booted_only=1
fi
printf '%s %s\n' "$(tree_key)" "$(readlink -f /run/current-system)" > "$STAMP"

finished $(( ${EPOCHREALTIME/[.,]/} - started ))
(( booted_only )) && warn "Aktivering feilet, ny versjon gjelder fra neste oppstart"
needs_reboot && warn "Start maskinen på nytt for å fullføre"
exit 0
