#!/usr/bin/env bash

# NixOS installer: panel-signed boot chain, LUKS2 root on ext4, zram instead of swap.
# Destructive: wipes the chosen disk completely.

set -euo pipefail

die() { echo "[ERROR] $*" >&2; exit 1; }
log() { echo "[INFO] $*" >&2; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

confirm() { return 0; }

# Fastest metadata-free NVMe LBA format.
nvme_fastest_lbaf() {
  require_cmd nvme
  local now best
  IFS=: read -r now best < <(nvme id-ns "$1" | awk '
    $1 != "lbaf" { next }
    / \(in use\)/ { now = $2 }
    $4 != "ms:0" { next }
    { ds = substr($5, 7) + 0; rp = substr($6, 4); sub(/^0x/, "", rp); rp += 0 }
    ds > 12 { next }
    best == "" || rp < brp || (rp == brp && ds > bds) { best = $2; brp = rp; bds = ds }
    END { print now ":" best }')
  [[ -n "$best" && "$best" != "$now" ]] || return 0
  log "Switching $1 to LBA format $best"
  nvme format "$1" --lbaf="$best" --force || log "LBA format switch refused; keeping format $now"
  udevadm settle
}

usage() {
  cat <<EOF
Usage: sudo $(basename "$0") [--disk /dev/xxx] [--hostname NAME] [--user NAME] [--luks-passphrase PASS | --luks-passphrase-file FILE | --luks-passphrase-stdin | --prompt-luks-passphrase]

Performs a clean NixOS installation on the selected disk with:
- GPT: ${ESP_SIZE}iB ESP (FAT32, unencrypted), rest LUKS2 (argon2id, 4K sectors) for root
- Root filesystem: ext4 (fast_commit, noatime, lazytime), tuned to the detected disk:
  NVMe switched to its fastest LBA format, discard and dm-crypt workqueue bypass on SSDs
- Bootloader: systemd-boot, signed by the Nixly panel
- Swap: zram (no swap partition)
- Secure Boot: firmware stays in setup mode until nixlyos-secureboot enroll

Options:
  --disk                   Device to install to (e.g., /dev/nvme0n1 or /dev/sda)
  --hostname               Hostname to set (default: nixlyos)
  --user                   Target user owning ~/.local/nixlyos (default: total)
  --profile                Profile from the Nixly panel (default: asked)
  --luks-passphrase        LUKS passphrase (non-interactive)
  --luks-passphrase-file   File containing LUKS passphrase
  --luks-passphrase-stdin  Read LUKS passphrase from stdin (non-interactive; safe from argv)
  --no-prompt              Skip interactive passphrase prompt (generate random passphrase)

By default, the installer prompts for a LUKS passphrase interactively.

Notes on encryption:
- ESP (/boot, FAT32) cannot be encrypted by UEFI design.
- All OS data, including /, is encrypted with modern LUKS2 (argon2id).
EOF
}

DISK=""
HOSTNAME="nixlyos"
LUKS_PASSPHRASE=""
LUKS_PASSPHRASE_FILE=""
LUKS_PASSPHRASE_STDIN=0
NO_PROMPT=0
NIXLY_USER="total"
PROFILE=""
# Room for three kernels.
ESP_SIZE="1G"


while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0;;
    --disk) DISK=${2:-}; shift 2;;
    --hostname) HOSTNAME=${2:-}; shift 2;;
    --user) NIXLY_USER=${2:-}; shift 2;;
    --profile) PROFILE=${2:-}; shift 2;;
    --luks-passphrase) LUKS_PASSPHRASE=${2:-}; shift 2;;
    --luks-passphrase-file) LUKS_PASSPHRASE_FILE=${2:-}; shift 2;;
    --luks-passphrase-stdin) LUKS_PASSPHRASE_STDIN=1; shift 1;;
    --no-prompt) NO_PROMPT=1; shift 1;;
    *) die "Unknown argument: $1";;
  esac
done

# Preconditions
for c in sgdisk udevadm lsblk awk sed grep mkfs.vfat mkfs.ext4 cryptsetup blkid mount umount nixos-generate-config nixos-install base64; do
  require_cmd "$c"
done

[[ $EUID -eq 0 ]] || die "Run as root (sudo)."

# UEFI in setup mode for enrollment.
[[ -d /sys/firmware/efi ]] || die "System is not booted in UEFI mode. This installer requires UEFI."

SB_VAR="/sys/firmware/efi/efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c"
SM_VAR="/sys/firmware/efi/efivars/SetupMode-8be4df61-93ca-11d2-aa0d-00e098032b8c"

SB_ENABLED=0
SETUP_MODE=0

if [[ -f "$SB_VAR" ]]; then
  SB_BYTE=$(od -An -t u1 -j4 -N1 "$SB_VAR" | tr -d ' ')
  [[ "$SB_BYTE" == "1" ]] && SB_ENABLED=1
fi

if [[ -f "$SM_VAR" ]]; then
  SM_BYTE=$(od -An -t u1 -j4 -N1 "$SM_VAR" | tr -d ' ')
  [[ "$SM_BYTE" == "1" ]] && SETUP_MODE=1
fi

if [[ "$SETUP_MODE" -eq 1 ]]; then
  log "Secure Boot er i Setup Mode – klar for nøkkelregistrering"
else
  die "Secure Boot er ikke i Setup Mode. Gå inn i BIOS/UEFI og sett Secure Boot til Setup Mode før du kjører dette scriptet."
fi

SELF_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# The Nixly panel holds the profiles.
source "$SELF_DIR/scripts/install-panel.sh"

if [[ -z "$PROFILE" ]]; then
  PROFILE=$(choose_profile) || log "Nixly-panelet svarer ikke – installerer uten profil"
fi

# Auto-pick a disk if not provided: prefer NVMe/SSD, size >= 32G, non-removable.
if [[ -z "$DISK" ]]; then
  CANDIDATE=$(lsblk -dn -o NAME,TYPE,RM,SIZE,ROTA | awk '$2=="disk" && $3==0 {print $0}' | awk '(index($1,"nvme")==1 || $5==0) {print $1}' | head -n1)
  [[ -n "$CANDIDATE" ]] || die "Could not auto-detect a suitable disk. Use --disk /dev/XXX"
  DISK="/dev/${CANDIDATE}"
  log "Auto-selected disk: $DISK"
fi

[[ -b "$DISK" ]] || die "Disk not found: $DISK"

# TRAN last: it can be empty.
read -r ROTATIONAL DISCARD_MAX TRAN < <(lsblk -dnbo ROTA,DISC-MAX,TRAN "$DISK")
log "Disk $DISK: transport=${TRAN:-none} rotational=$ROTATIONAL discard_max=$DISCARD_MAX"

log "Proceeding to ERASE ALL DATA on $DISK (non-interactive)"

# Unmount anything under /mnt from previous attempts
if mountpoint -q /mnt; then
  log "Unmounting previous /mnt"
  umount -R /mnt || true
fi

swapoff -a || true

if [[ "$TRAN" == nvme ]]; then
  nvme_fastest_lbaf "$DISK"
fi

log "Wiping partition table on $DISK"
sgdisk --zap-all "$DISK"

# Aligned end keeps 4K LUKS sectors valid.
log "Creating GPT partitions (ESP + LUKS root)"
sgdisk --align-end \
  -n "1:0:+$ESP_SIZE" -t 1:ef00 -c 1:NIXESP \
  -n 2:0:0 -c 2:NIXLUKS \
  "$DISK"

# Resolve partition paths (handle nvme pN suffix)
P1=$(lsblk -no PATH -r "$DISK" | sed -n '2p')
P2=$(lsblk -no PATH -r "$DISK" | sed -n '3p')
[[ -n "$P1" && -n "$P2" ]] || die "Failed to resolve partition paths for $DISK"

log "Formatting ESP (FAT32): $P1"
mkfs.vfat -F32 -n NIXBOOT "$P1"

log "Preparing LUKS2 passphrase"
# Precedence: file > arg > stdin > interactive prompt > generate
if [[ -n "$LUKS_PASSPHRASE_FILE" ]]; then
  [[ -f "$LUKS_PASSPHRASE_FILE" ]] || die "Passphrase file not found: $LUKS_PASSPHRASE_FILE"
  LUKS_PASSPHRASE=$(cat "$LUKS_PASSPHRASE_FILE")
elif [[ -n "$LUKS_PASSPHRASE" ]]; then
  : # already set via --luks-passphrase
elif [[ "$LUKS_PASSPHRASE_STDIN" -eq 1 ]]; then
  if [[ -t 0 ]]; then
    die "--luks-passphrase-stdin requested but stdin is a TTY."
  fi
  IFS= read -r LUKS_PASSPHRASE || die "Failed reading passphrase from stdin"
elif [[ "$NO_PROMPT" -eq 1 ]]; then
  # Generate strong random passphrase
  LUKS_PASSPHRASE=$(head -c 64 /dev/urandom | base64 -w0)
  log "Generated LUKS passphrase (SAVE THIS NOW):"
  echo "$LUKS_PASSPHRASE"
else
  # Default: prompt interactively
  read -rs -p "Enter LUKS passphrase: " LUKS_PASSPHRASE; echo
  read -rs -p "Confirm LUKS passphrase: " LUKS_PASSPHRASE_CONFIRM; echo
  [[ -n "$LUKS_PASSPHRASE" ]] || die "Empty passphrase not allowed"
  [[ "$LUKS_PASSPHRASE" == "$LUKS_PASSPHRASE_CONFIRM" ]] || die "Passphrases do not match"
fi

log "Setting up LUKS2 on $P2 (argon2id, high iteration time)"
printf '%s' "$LUKS_PASSPHRASE" | cryptsetup luksFormat \
  --batch-mode \
  --type luks2 \
  --sector-size 4096 \
  --cipher aes-xts-plain64 \
  --key-size 512 \
  --pbkdf argon2id \
  --iter-time 5000 \
  --hash sha512 \
  --key-file - \
  "$P2"

# Header flags apply every unlock.
OPEN_FLAGS=(--persistent)
(( DISCARD_MAX > 0 )) && OPEN_FLAGS+=(--allow-discards)
(( ROTATIONAL == 0 )) && OPEN_FLAGS+=(--perf-no_read_workqueue --perf-no_write_workqueue)

log "Opening LUKS container as cryptroot (${OPEN_FLAGS[*]})"
printf '%s' "$LUKS_PASSPHRASE" | cryptsetup open \
  --type luks \
  "${OPEN_FLAGS[@]}" \
  --key-file - \
  "$P2" cryptroot

# Cheap fsync, no background zeroing.
log "Creating ext4 filesystem on /dev/mapper/cryptroot"
mkfs.ext4 -L nixos \
  -O 64bit,metadata_csum,dir_index,extent,fast_commit \
  -E lazy_itable_init=0 \
  /dev/mapper/cryptroot

log "Mounting target filesystem"
mount -o noatime,lazytime,commit=120 /dev/mapper/cryptroot /mnt
mkdir -p /mnt/boot
mount "$P1" /mnt/boot

log "Generating NixOS hardware configuration"
nixos-generate-config --root /mnt

HWC=/mnt/etc/nixos/hardware-configuration.nix

# Machine state lives here.
NIXLY_DIR="/mnt/home/$NIXLY_USER/.local/nixlyos"

log "Writing machine state to $NIXLY_DIR"
mkdir -p "$NIXLY_DIR/hardware"
cp "$HWC" "$NIXLY_DIR/hardware/hardware-configuration.nix"

STATE_VERSION=$(grep -oP 'system\.stateVersion = "\K[0-9]{2}\.[0-9]{2}' /mnt/etc/nixos/configuration.nix || echo "26.05")

# Without a profile: the panel's main.
legacy_flake() {
  cat > "$NIXLY_DIR/flake.nix" <<FLAKE
{
  description = "NixlyOS machine";

  inputs = {
    nixlypkgs.url = "git+$NIXLY_PANEL/source.git";
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
}

# Flake reads custom/ at install.
mkdir -p "$NIXLY_DIR/custom"

cat > "$NIXLY_DIR/custom/inputs.nix" <<'CUSTOM'
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

cat > "$NIXLY_DIR/custom/modules.nix" <<'CUSTOM'
# Your own NixOS module. Anything you would normally put in configuration.nix
# goes here: packages, services, imports of your own module files in custom/.
# Inputs declared in custom/inputs.nix arrive through the `inputs` argument.
# Options the NixlyOS core owns (display manager, portals, secure boot, ...)
# are fenced off and refuse to build if set here.
{ ... }:

{
}
CUSTOM

# Keybindings: nixlytile reads and inotify-watches this file directly, so an
# edit applies immediately. Lives at the root, not in custom/.
cp "$SELF_DIR/scripts/bindings-default.conf" "$NIXLY_DIR/bindings.conf"

cat > "$NIXLY_DIR/local.nix" <<'LOCAL'
# Per-machine overrides. Anything set here stays local and never reaches the
# public nixlypkgs repo — passwords, keys and machine-specific tweaks belong
# here. Empty by default.
{ ... }:

{
}
LOCAL

log "Detecting CPU/GPU and writing hardware data"
REGISTER="$SELF_DIR/scripts/laptop-register" bash "$SELF_DIR/scripts/detect-hw.sh" "$NIXLY_DIR/hardware"

if [[ -n "$PROFILE" ]] && panel flake "$HOSTNAME" "$NIXLY_USER" "$STATE_VERSION" "$PROFILE"; then
  log "Profil $PROFILE fra Nixly-panelet"
else
  log "Skriver flake uten profil"
  legacy_flake
fi

# The default user is uid 1000; nixos-install runs before the user exists.
chown -R 1000:100 "/mnt/home/$NIXLY_USER"

log "Installing NixOS from flake $NIXLY_DIR#nixlyos (no root password)"
nixos-install --no-root-password --root /mnt --flake "$NIXLY_DIR#nixlyos"

log "Installation complete. Unmounting and closing LUKS."
umount -R /mnt || true
cryptsetup close cryptroot || true

log "Done. Reboot, then enroll the panel's keys: sudo nixlyos-secureboot enroll"
