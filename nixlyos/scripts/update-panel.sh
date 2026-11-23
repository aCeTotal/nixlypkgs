# Panel hooks for nixlyos-update.

# Machines follow a published profile.
panel_join() {
  [[ -f "$FLAKE/profile" ]] && return 0
  if ! nixlyos-panel adopt >>"$log" 2>&1; then
    echo "Velg en publisert profil med: nixlyos-panel use <profil>" | error_block "Maskinen følger ingen profil i Nixly-panelet"
    exit 1
  fi
  tick "Koblet til profilen $(<"$FLAKE/profile") i Nixly-panelet"
}

newer_release() { nixlyos-panel moved 2>>"$log"; }

# The panel decides every revision.
lock_panel() {
  local branch
  spin_start "Henter utgivelse fra Nixly-panelet"
  cp "$FLAKE/flake.lock" "$tmp/old.lock" 2>/dev/null || : > "$tmp/old.lock"
  if ! nixlyos-panel pin >>"$log" 2>&1 || ! (cd "$FLAKE" && nix flake lock) >>"$log" 2>&1; then
    spin_stop
    cp "$tmp/old.lock" "$FLAKE/flake.lock"
    tail -20 "$log" | error_block "Kunne ikke hente utgivelsen fra panelet"
    exit 1
  fi
  branch=$(nixlyos-panel branch)
  tick "${branch^}-utgivelse hentet fra panelet"
}
