#!/usr/bin/env bash
# Migrates a machine from the old local flake repo (~/.nixlyos) to the new
# architecture: a tiny machine flake in ~/.local/nixlyos that pulls everything
# from nixlypkgs via lib.mkNixlySystem. The old repo is left untouched so the
# previous generation stays bootable; remove it manually once the new system
# is verified.
#
# Run as the normal user (sudo is used for activation only):
#   bash migrate-to-local.sh
set -euo pipefail

die() { echo "[ERROR] $*" >&2; exit 1; }
log() { echo "[INFO] $*" >&2; }

OLD="${OLD_NIXLYOS_DIR:-$HOME/.nixlyos}"
NEW="${NIXLYOS_DIR:-$HOME/.local/nixlyos}"

[[ $EUID -ne 0 ]] || die "Kjør som vanlig bruker, ikke root."
[[ -f "$OLD/flake.nix" ]] || die "Fant ikke gammelt repo i $OLD."
[[ -e "$NEW/flake.nix" ]] && die "$NEW finnes allerede — maskinen ser ut til å være migrert. (Slett $NEW og kjør på nytt hvis en tidligere migrering ble avbrutt.)"
for c in curl tar nix sudo; do command -v "$c" >/dev/null || die "Mangler kommando: $c"; done

# Per-machine data carried over from the old repo.
HOSTNAME=$(grep -oP 'networking\.hostName\s*=\s*"\K[^"]+' "$OLD/configuration.nix" || true)
[[ -n "$HOSTNAME" ]] || HOSTNAME=$(hostname)
STATE_VERSION=$(grep -oP 'system\.stateVersion\s*=\s*"\K[0-9]{2}\.[0-9]{2}' "$OLD/configuration.nix" || true)
[[ -n "$STATE_VERSION" ]] || die "Fant ikke system.stateVersion i $OLD/configuration.nix."
HWC="$OLD/hardware-configuration.nix"
[[ -f "$HWC" ]] || HWC=/etc/nixos/hardware-configuration.nix
[[ -f "$HWC" ]] || die "Fant ingen hardware-configuration.nix."
NIXLY_USER=$USER

log "hostname=$HOSTNAME  user=$NIXLY_USER  stateVersion=$STATE_VERSION"

# The helper scripts (detect-hw, laptop-register, default bindings) come from
# nixlypkgs main, so the migration always uses the current versions.
tmp=$(mktemp -d -t nixlyos-migrate.XXXXXX)
# Stage everything next to $NEW and move it into place only after the build
# succeeds, so an aborted run never leaves a half-finished $NEW behind.
mkdir -p "$(dirname "$NEW")"
STAGE=$(mktemp -d "$NEW.tmp.XXXXXX")
trap 'rm -rf "$tmp" "$STAGE"' EXIT
log "Henter nixlypkgs main"
curl -fsSL https://github.com/aCeTotal/nixlypkgs/archive/refs/heads/main.tar.gz \
  | tar -xz -C "$tmp"
SRC="$tmp/nixlypkgs-main/nixlyos"
[[ -f "$SRC/scripts/detect-hw.sh" ]] || die "Uventet tarball-innhold."

log "Skriver maskinflake til $STAGE"
mkdir -p "$STAGE/hardware" "$STAGE/custom"
cp "$HWC" "$STAGE/hardware/hardware-configuration.nix"

cat > "$STAGE/flake.nix" <<FLAKE
{
  description = "NixlyOS machine";

  inputs = {
    # Everything lives in nixlypkgs (main); its flake.lock decides every
    # input revision this machine runs.
    nixlypkgs.url = "github:aCeTotal/nixlypkgs";
    # BEGIN USER INPUTS (generated from custom/inputs.nix — edit that instead)
    # END USER INPUTS
  };

  outputs = inputs@{ nixlypkgs, ... }: {
    nixosConfigurations.nixlyos = nixlypkgs.lib.mkNixlySystem {
      hostName = "$HOSTNAME";
      username = "$NIXLY_USER";
      stateVersion = "$STATE_VERSION";
      hardwareDir = ./hardware;
      localConfig = ./local.nix;
      userModules = ./custom/modules.nix;
      userInputs = builtins.removeAttrs inputs [ "nixlypkgs" "self" ];
    };
  };
}
FLAKE

cat > "$STAGE/custom/inputs.nix" <<'CUSTOM'
# Extra flake inputs for this machine, pulled into flake.nix on every update.
# One attribute per input:
#
#   nixvim = "github:nix-community/nixvim";                     # a flake
#   dotfiles = { url = "github:me/dotfiles"; flake = false; };  # plain source
#
# Names NixlyOS uses itself (nixpkgs, home-manager, nixlypkgs, ...) are
# reserved. Reach the inputs from custom/modules.nix via the `inputs` arg.
{
}
CUSTOM

cat > "$STAGE/custom/modules.nix" <<'CUSTOM'
# Your own NixOS module. Anything you would normally put in configuration.nix
# goes here: packages, services, imports of your own module files in custom/.
# Inputs declared in custom/inputs.nix arrive through the `inputs` argument.
# Options the NixlyOS core owns (display manager, portals, secure boot, ...)
# are fenced off and refuse to build if set here.
{ ... }:

{
}
CUSTOM

cat > "$STAGE/local.nix" <<'LOCAL'
# Per-machine overrides. Anything set here stays local and never reaches the
# public nixlypkgs repo — passwords, keys and machine-specific tweaks belong
# here. Empty by default.
{ ... }:

{
}
LOCAL

# Keybindings: nixlytile reads and inotify-watches this file directly.
cp "$SRC/scripts/bindings-default.conf" "$STAGE/bindings.conf"

log "Kjører hardware-deteksjon"
REGISTER="$SRC/scripts/laptop-register" bash "$SRC/scripts/detect-hw.sh" "$STAGE/hardware"

# cd instead of --flake: works on both old and new (pinned) nix CLI.
log "Låser flake"
(cd "$STAGE" && nix flake lock)

# Build against cache.aceclan.no so everything prebuilt is substituted instead
# of compiled locally. The user is in trusted-users on the old arch, so the
# daemon accepts the extra substituter.
ATTR="$STAGE#nixosConfigurations.nixlyos.config.system.build.toplevel"
log "Bygger nytt system (henter fra cache.aceclan.no)"
sys=$(nix build --no-link --print-out-paths --keep-going "$ATTR" \
  --max-jobs "$(nproc)" --cores 0 \
  --option extra-substituters https://cache.aceclan.no \
  --option extra-trusted-public-keys cache.aceclan.no-1:qfGAXabgsofKSAqId9sqqbPlQic4l7gOGeWPrqUg3ak= \
  --option max-substitution-jobs 128 \
  --option http-connections 128 \
  --option connect-timeout 3 \
  --option fallback true)

# Build succeeded — move the finished flake into place before activating.
mv -T "$STAGE" "$NEW"

log "Aktiverer"
sudo nix-env -p /nix/var/nix/profiles/system --set "$sys"
if ! sudo systemd-run --collect --no-ask-password --pipe --wait \
    --service-type=exec --unit="nixlyos-migrate-$$" \
    "$sys/bin/switch-to-configuration" switch; then
  sudo "$sys/bin/switch-to-configuration" boot
  echo "Aktivering feilet — ny versjon gjelder fra neste boot." >&2
fi

log "Ferdig. Gamle $OLD er urørt; slett den når det nye systemet er verifisert."
echo "Omstart anbefales (ny kjerne/moduler)."
