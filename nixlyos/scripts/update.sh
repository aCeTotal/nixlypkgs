# NixlyOS update: newest first, else last working.
set -euo pipefail

FLAKE="${NIXLYOS_DIR:-$HOME/.local/nixlyos}"
[[ -f "$FLAKE/flake.nix" ]] || { echo "error: missing $FLAKE/flake.nix" >&2; exit 1; }

STATE="${XDG_STATE_HOME:-$HOME/.local/state}/nixlyos"
STAMP="$STATE/last-build"
STAGEDIR="$STATE/stage"
EVAL_TIME="$STATE/eval-us"
PINS="$FLAKE/pins.nix"
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
trap 'spin_stop; [ -n "$keepalive" ] && kill -- -"$keepalive" 2>/dev/null; [ -z "$eval_pid" ] || kill "$eval_pid" 2>/dev/null || :; (( tty )) && printf "\033[?25h\033[?7h\n" >&2; rm -rf "$tmp"' EXIT

# Same file list as stage.sh.
tree_key() {
  cat "$FLAKE"/flake.nix "$FLAKE"/flake.lock "$FLAKE"/local.nix "$FLAKE"/pins.nix \
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

# One parallel ls-remote per moving input.
remote_moved() {
  local specs repo ref rev n=0 j pids=()
  specs=$(jq -r '
    .nodes | to_entries[]
    | select(.key == "nixlypkgs" or .key == "nixos-stable" or .key == "home-manager")
    | select(.value.original.type? == "github")
    | "\(.value.original.owner)/\(.value.original.repo)\t\(.value.original.ref // "HEAD")\t\(.value.locked.rev)"
  ' "$FLAKE/flake.lock" 2>/dev/null) || return 0
  [ "$(grep -c . <<< "$specs")" -eq 3 ] || return 0
  while IFS=$'\t' read -r repo ref rev; do
    printf '%s' "$rev" > "$tmp/want.$n"
    [ "$ref" = HEAD ] || ref="refs/heads/$ref"
    { git ls-remote "https://github.com/$repo" "$ref" 2>/dev/null | cut -f1 | head -1 > "$tmp/head.$n"; } &
    pids+=($!)
    n=$((n + 1))
  done <<< "$specs"
  wait "${pids[@]}" 2>/dev/null || :
  for (( j = 0; j < n; j++ )); do
    [ -s "$tmp/head.$j" ] || return 0
    [ "$(tr -d '\n' < "$tmp/head.$j")" = "$(<"$tmp/want.$j")" ] || return 0
  done
  return 1
}

stamp_matches() {
  local key="" built=""
  [ -s "$STAMP" ] && read -r key built < "$STAMP"
  [ -s "$FLAKE/flake.lock" ] && [ "$key" = "$(tree_key)" ] && [ "$built" = "$running" ]
}

check_remote() {
  stamp_matches || return 0
  spin_start "Ser etter oppdateringer"
  remote_moved && { tick "Nye versjoner tilgjengelig"; return 0; }
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

# Password once, kept warm through long builds.
sudo_start() {
  if ! sudo -n true 2>/dev/null; then
    if (( tty )); then ask_password; else sudo -v; fi
  fi
  setsid bash -c 'while sudo -n true; do sleep 50; done' </dev/null >/dev/null 2>&1 &
  keepalive=$!
}

free_disk() {
  (( $(df --output=avail /nix | tail -1) < MIN_FREE_KIB )) || return 0
  spin_start "Rydder gamle generasjoner"
  { sudo nix-env -p /nix/var/nix/profiles/system --delete-generations "$KEEP_GENERATIONS"; } >>"$log" 2>&1
  nix-collect-garbage --delete-older-than "$KEEP_GENERATIONS" >>"$log" 2>&1 || :
  tick "Diskplass frigjort"
}

# Tested nixlypkgs pin, then stable/HM heads.
lock_newest() {
  spin_start "Henter nyeste versjoner"
  cp "$FLAKE/flake.lock" "$tmp/old.lock" 2>/dev/null || : > "$tmp/old.lock"
  rm -f "$FLAKE/flake.lock"
  if ! (cd "$FLAKE" && nix flake lock --refresh) >>"$log" 2>&1; then
    spin_stop
    cp "$tmp/old.lock" "$FLAKE/flake.lock"
    tail -20 "$log" | error_block "Kunne ikke hente nye versjoner"
    exit 1
  fi
  cp "$FLAKE/flake.lock" "$tmp/tested.lock"
  (cd "$FLAKE" && nix flake update --refresh nixlypkgs/nixos-stable nixlypkgs/home-manager) >>"$log" 2>&1 ||
    cp "$tmp/tested.lock" "$FLAKE/flake.lock"
  tick "Nyeste versjoner hentet"
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

# No pins; staged build, else eval.
fresh_start() {
  rm -f "$PINS"
  : > "$tmp/pinned"
  staged=$(staged_sys) || eval_start
}

# Every core, wide substitution fan-out.
build_sys() {
  if [ -n "$staged" ]; then
    printf '%s\n' "$staged" > "$tmp/out"
    step_done "Ferdig bygget i bakgrunnen"
    return 0
  fi
  : > "$tmp/failed"
  eval_wait || return
  local rc=0
  # Braces put view pid in $!.
  {
    nix build --no-link --print-out-paths --keep-going "$(<"$tmp/drv")^*" \
      --max-jobs "$(nproc)" --cores 0 \
      --option substituters 'https://cache.aceclan.no?priority=5 https://cache.nixos.org' \
      --option extra-trusted-public-keys cache.aceclan.no-1:qfGAXabgsofKSAqId9sqqbPlQic4l7gOGeWPrqUg3ak= \
      --option max-substitution-jobs 128 \
      --option http-connections 128 \
      --option connect-timeout 3 \
      --option download-buffer-size 536870912 \
      --option fallback true \
      --log-format internal-json \
      >"$tmp/out"
  } 2> >(LC_ALL=C awk -f "$PROGRESS_AWK" 2>>"$log" | render_progress "$tmp/failed") || rc=$?
  wait $! 2>/dev/null || :
  return "$rc"
}

# Running closure's path and version of $1.
last_working() {
  awk -v n="$1" 'index(substr($0, 45), n "-") == 1 {
    v = substr($0, 46 + length(n))
    if (v ~ /^[0-9]/ && v !~ /-[a-zA-Z][a-zA-Z0-9]*$/) { print $0 "\t" v; exit }
  }' "$tmp/old.paths"
}

# Failed packages back to their running build.
pin_failed() {
  local name ver old oldver
  [ -s "$tmp/failed" ] || return 1
  while IFS=$'\t' read -r name ver; do
    IFS=$'\t' read -r old oldver < <(last_working "$name") || return 1
    printf '%s\t%s\t%s\t%s\n' "$name" "$oldver" "$ver" "$old" >> "$tmp/pinned"
  done < <(sed 's/\.drv$//' "$tmp/failed" | split_names | sort -u)
  [ "$(wc -l < "$tmp/pinned")" -eq "$(sort -u "$tmp/failed" | wc -l)" ] || return 1
  awk -F '\t' 'BEGIN { print "{" } { printf "  \"%s\" = \"%s\";\n", $1, $4 } END { print "}" }' \
    "$tmp/pinned" > "$PINS"
  warn "$(cut -f1 "$tmp/pinned" | paste -sd' ') feilet, prøver forrige versjon"
}

# Newest build, failures pinned.
attempt() {
  build_sys && return 0
  pin_failed && eval_start && build_sys
}

# Retry on tested stable/HM.
attempt_tested() {
  cmp -s "$tmp/tested.lock" "$FLAKE/flake.lock" && return 1
  cp "$tmp/tested.lock" "$FLAKE/flake.lock"
  warn "Nyeste nixos-stable/home-manager feilet, prøver testet versjon"
  fresh_start
  attempt
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
  rm -f "$PINS"
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
running=$(readlink -f /run/current-system)
check_remote
nix path-info -r "$running" > "$tmp/old.paths" &
paths_pid=$!
lock_newest
stamp_matches && up_to_date
fresh_start
sudo_start
free_disk
wait "$paths_pid"

attempt || attempt_tested || fail
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
