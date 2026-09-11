# Shared implementation behind install_htpc / install_desktop (mode comes
# in via NIXLY_MODE). Switches the machine between the two configuration
# sets by writing nixlyos.mode into ~/.local/nixlyos/local.nix, rebuilding
# and activating. A machine still on the old ~/.nixlyos architecture is
# converted first by running the stock migration script (nixlyos-migrate),
# and the old repo is archived once the new system is active.
#
# Safe by construction: local.nix edits are backed up, parse-checked and
# semantically verified (nix eval of nixlyos.mode) before anything is
# built; a failed activation falls back to switch-to-configuration boot,
# and the previous generation always remains in the systemd-boot menu.

MODE="${NIXLY_MODE:?run install_htpc or install_desktop instead}"
case "$MODE" in
  htpc|desktop) ;;
  *) echo "error: ukjent mode: $MODE" >&2; exit 1 ;;
esac

die() { echo "[ERROR] $*" >&2; exit 1; }
log() { echo "[INFO] $*" >&2; }

FLAKE="${NIXLYOS_DIR:-$HOME/.local/nixlyos}"
OLD="${OLD_NIXLYOS_DIR:-$HOME/.nixlyos}"

[[ $EUID -ne 0 ]] || die "Kjør som vanlig bruker; sudo brukes kun til aktivering."

# ── Old architecture? Convert with the stock migration script first. ──
migrated=""
if [[ ! -f "$FLAKE/flake.nix" ]]; then
  [[ -f "$OLD/flake.nix" ]] || die "Fant hverken $FLAKE/flake.nix eller $OLD/flake.nix — er dette en NixlyOS-maskin?"
  log "Gammel arkitektur ($OLD) i bruk — konverterer til nixlypkgs først"
  nixlyos-migrate
  migrated=1
fi

# ── Write nixlyos.mode into local.nix. ──
LOCAL="$FLAKE/local.nix"
[[ -f "$LOCAL" ]] || printf '{ ... }:\n\n{\n}\n' > "$LOCAL"

cur=$(grep -oP '^[^#]*nixlyos\.mode\s*=\s*"\K[^"]+' "$LOCAL" | head -1 || true)
edited=""
if [[ "$cur" != "$MODE" ]]; then
  cp "$LOCAL" "$LOCAL.bak"
  edited=1
  if [[ -n "$cur" ]]; then
    sed -Ei "s|(nixlyos\.mode[[:space:]]*=[[:space:]]*\")[^\"]*\"|\1$MODE\"|" "$LOCAL"
  else
    # Insert right before the attrset's final closing brace.
    awk -v mode="$MODE" '
      { lines[NR] = $0 }
      END {
        last = 0
        for (i = NR; i >= 1; i--)
          if (lines[i] ~ /^[[:space:]]*}[[:space:]]*$/) { last = i; break }
        for (i = 1; i <= NR; i++) {
          if (i == last) print "  nixlyos.mode = \"" mode "\";"
          print lines[i]
        }
      }' "$LOCAL.bak" > "$LOCAL"
  fi
  nix-instantiate --parse "$LOCAL" >/dev/null 2>&1 || {
    cp "$LOCAL.bak" "$LOCAL"
    die "local.nix ble ugyldig etter redigering — rullet tilbake. Sett nixlyos.mode = \"$MODE\" manuelt i $LOCAL og kjør på nytt."
  }
fi

# ── Semantic check before building anything. ──
log "Verifiserer at nixlyos.mode = \"$MODE\" tar effekt"
got=$(cd "$FLAKE" && nix eval --raw ".#nixosConfigurations.nixlyos.config.nixlyos.mode" 2>/dev/null || true)
if [[ "$got" != "$MODE" ]]; then
  if [[ -n "$edited" ]]; then cp "$LOCAL.bak" "$LOCAL"; fi
  die "Konfigurasjonen evaluerer ikke til $MODE (fikk: '${got:-tom}'). Ingen endring aktivert."
fi

# ── Build + activate, same flags and pattern as nixlyos-update. ──
ATTR="$FLAKE#nixosConfigurations.nixlyos.config.system.build.toplevel"
log "Bygger $MODE-systemet (henter fra cache.aceclan.no)"
sys=$(nix build --no-link --print-out-paths --keep-going "$ATTR" \
  --max-jobs "$(nproc)" --cores 0 \
  --option extra-substituters https://cache.aceclan.no \
  --option extra-trusted-public-keys cache.aceclan.no-1:qfGAXabgsofKSAqId9sqqbPlQic4l7gOGeWPrqUg3ak= \
  --option max-substitution-jobs 128 \
  --option http-connections 128 \
  --option connect-timeout 3 \
  --option fallback true)

log "Aktiverer (sudo)"
sudo nix-env -p /nix/var/nix/profiles/system --set "$sys"
switched=1
if ! sudo systemd-run --collect --no-ask-password --pipe --wait \
    --service-type=exec --unit="nixlyos-setmode-$$" \
    "$sys/bin/switch-to-configuration" switch; then
  switched=""
  sudo "$sys/bin/switch-to-configuration" boot
  log "Aktivering feilet — $MODE gjelder fra neste boot."
fi

if [[ -n "$switched" ]]; then
  marker=$(cat /etc/nixlyos-mode 2>/dev/null || true)
  [[ "$marker" == "$MODE" ]] || die "Aktivert system melder mode '$marker', ikke '$MODE' — sjekk $LOCAL."
fi

# ── The old repo is dropped once the nixpkgs-architecture system runs. ──
if [[ -e "$OLD" ]]; then
  bak="$OLD.migrated.$(date +%Y%m%d%H%M%S)"
  mv "$OLD" "$bak"
  log "Gamle $OLD er tatt ut av bruk — arkivert som $bak (slett når alt er verifisert)."
fi

log "Ferdig: maskinen kjører nå $MODE-konfigurasjonen."
if [[ "$MODE" == htpc ]]; then
  log "Reboot anbefales — HTPC-økten (autologin + Steam Big Picture) starter ved neste innlogging."
elif [[ -n "$migrated" ]]; then
  log "Reboot anbefales (ny kjerne/moduler etter konvertering)."
fi
