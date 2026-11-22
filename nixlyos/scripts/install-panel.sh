# Installer side of the Nixly panel.
NIXLY_PANEL=$(nix-instantiate --eval --json "$SELF_DIR/lib/panel.nix" -A url | tr -d '"')

panel() {
  NIXLYOS_DIR="$NIXLY_DIR" NIXLY_PANEL="$NIXLY_PANEL" \
    nix-shell -p jq curl --run "bash $(printf '%q ' "$SELF_DIR/scripts/panel.sh" "$@")"
}

choose_profile() {
  local default=desktop choice name title description i
  local -a profiles
  [[ $(cat /sys/class/dmi/id/chassis_type 2>/dev/null) =~ ^(8|9|10|14|31|32)$ ]] && default=laptop
  mapfile -t profiles < <(panel profiles 2>/dev/null)
  (( ${#profiles[@]} > 0 )) || return 1
  echo "Profiler i Nixly-panelet:" >&2
  for i in "${!profiles[@]}"; do
    IFS=$'\t' read -r name title _ description <<< "${profiles[$i]}"
    printf '  %2d) %-12s %-10s %s\n' $((i + 1)) "$name" "$title" "$description" >&2
  done
  read -rp "Velg profil [$default]: " choice
  choice=${choice:-$default}
  [[ $choice =~ ^[0-9]+$ ]] && choice=$(cut -f1 <<< "${profiles[$((choice - 1))]}")
  echo "$choice"
}
