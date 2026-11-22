# Panel hooks for nixlyos-update.
panel_managed() { [[ -f "$FLAKE/profile" ]]; }

# Pre-panel machines join once.
panel_adopt() {
  panel_managed && return 0
  nixlyos-panel adopt >>"$log" 2>&1 || return 0
  tick "Koblet til profilen $(<"$FLAKE/profile") i Nixly-panelet"
}

newer_release() {
  if panel_managed; then nixlyos-panel moved 2>>"$log"; else remote_moved; fi
}

# The panel decides every revision.
lock_panel() {
  spin_start "Henter utgivelse fra Nixly-panelet"
  cp "$FLAKE/flake.lock" "$tmp/old.lock" 2>/dev/null || : > "$tmp/old.lock"
  if ! nixlyos-panel pin >>"$log" 2>&1 || ! (cd "$FLAKE" && nix flake lock) >>"$log" 2>&1; then
    spin_stop
    cp "$tmp/old.lock" "$FLAKE/flake.lock"
    tail -20 "$log" | error_block "Kunne ikke hente utgivelsen fra panelet"
    exit 1
  fi
  cp "$FLAKE/flake.lock" "$tmp/tested.lock"
  tick "Utgivelse hentet fra panelet"
}
