#!/usr/bin/env bash

# NixOS installer: lanzaboote Secure Boot, LUKS2 root on ext4, zram instead of swap.
# Destructive: wipes the chosen disk completely.

set -euo pipefail

die() { echo "[ERROR] $*" >&2; exit 1; }
log() { echo "[INFO] $*" >&2; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

confirm() { return 0; }

usage() {
  cat <<EOF
Usage: sudo $(basename "$0") [--disk /dev/xxx] [--hostname NAME] [--user NAME] [--luks-passphrase PASS | --luks-passphrase-file FILE | --luks-passphrase-stdin | --prompt-luks-passphrase]

Performs a clean NixOS installation on the selected disk with:
- GPT: 512MiB ESP (FAT32, unencrypted), rest LUKS2 (argon2id) for root
- Root filesystem: ext4, SSD/NVMe optimized (noatime, discard=async)
- Bootloader: lanzaboote (Secure Boot via UEFI)
- Swap: zram (no swap partition)
- Secure Boot keys generated automatically

Options:
  --disk                   Device to install to (e.g., /dev/nvme0n1 or /dev/sda)
  --hostname               Hostname to set (default: nixlyos)
  --user                   Target user owning ~/.local/nixlyos (default: total)
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
CHANNEL="release"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0;;
    --disk) DISK=${2:-}; shift 2;;
    --hostname) HOSTNAME=${2:-}; shift 2;;
    --user) NIXLY_USER=${2:-}; shift 2;;
    --luks-passphrase) LUKS_PASSPHRASE=${2:-}; shift 2;;
    --luks-passphrase-file) LUKS_PASSPHRASE_FILE=${2:-}; shift 2;;
    --luks-passphrase-stdin) LUKS_PASSPHRASE_STDIN=1; shift 1;;
    --no-prompt) NO_PROMPT=1; shift 1;;
    *) die "Unknown argument: $1";;
  esac
done

# Preconditions
for c in parted sgdisk lsblk awk sed grep mkfs.vfat mkfs.ext4 cryptsetup blkid mount umount nixos-generate-config nixos-install base64; do
  require_cmd "$c"
done

[[ $EUID -eq 0 ]] || die "Run as root (sudo)."

# Verify UEFI boot and Secure Boot state (must be disabled or in Setup Mode for lanzaboote)
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

# Auto-pick a disk if not provided: prefer NVMe/SSD, size >= 32G, non-removable.
if [[ -z "$DISK" ]]; then
  CANDIDATE=$(lsblk -dn -o NAME,TYPE,RM,SIZE,ROTA | awk '$2=="disk" && $3==0 {print $0}' | awk '(index($1,"nvme")==1 || $5==0) {print $1}' | head -n1)
  [[ -n "$CANDIDATE" ]] || die "Could not auto-detect a suitable disk. Use --disk /dev/XXX"
  DISK="/dev/${CANDIDATE}"
  log "Auto-selected disk: $DISK"
fi

[[ -b "$DISK" ]] || die "Disk not found: $DISK"

log "Proceeding to ERASE ALL DATA on $DISK (non-interactive)"

# Unmount anything under /mnt from previous attempts
if mountpoint -q /mnt; then
  log "Unmounting previous /mnt"
  umount -R /mnt || true
fi

swapoff -a || true

log "Wiping partition table on $DISK"
sgdisk --zap-all "$DISK"

log "Creating GPT partitions (ESP + LUKS root)"
parted -s "$DISK" -- mklabel gpt \
  mkpart ESP fat32 1MiB 513MiB \
  set 1 esp on \
  name 1 NIXESP \
  mkpart primary 513MiB 100% \
  name 2 NIXLUKS

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
  --cipher aes-xts-plain64 \
  --key-size 512 \
  --pbkdf argon2id \
  --iter-time 5000 \
  --hash sha512 \
  --key-file - \
  "$P2"

log "Opening LUKS container as cryptroot (allow discards)"
printf '%s' "$LUKS_PASSPHRASE" | cryptsetup open \
  --type luks \
  --allow-discards \
  --key-file - \
  "$P2" cryptroot

log "Creating ext4 filesystem on /dev/mapper/cryptroot"
mkfs.ext4 -L nixos \
  -O 64bit,metadata_csum,dir_index,extent \
  /dev/mapper/cryptroot

log "Mounting target filesystem"
mount -o noatime,discard=async,commit=120 /dev/mapper/cryptroot /mnt
mkdir -p /mnt/boot
mount "$P1" /mnt/boot

log "Generating NixOS hardware configuration"
nixos-generate-config --root /mnt

HWC=/mnt/etc/nixos/hardware-configuration.nix

# The machine-local state: a tiny flake in ~/.local/nixlyos pointing at the
# nixlypkgs release channel, plus the hardware data. Everything else comes
# from nixlypkgs.
SELF_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
NIXLY_DIR="/mnt/home/$NIXLY_USER/.local/nixlyos"

log "Writing machine flake to $NIXLY_DIR"
mkdir -p "$NIXLY_DIR/hardware"
cp "$HWC" "$NIXLY_DIR/hardware/hardware-configuration.nix"

STATE_VERSION=$(grep -oP 'system\.stateVersion = "\K[0-9]{2}\.[0-9]{2}' /mnt/etc/nixos/configuration.nix || echo "26.05")

cat > "$NIXLY_DIR/flake.nix" <<FLAKE
{
  description = "NixlyOS machine";

  # Channel: release (tested) or testing (new changes) — switch with
  # nixlyos-channel, or from nixlycc. Everything else lives in nixlypkgs;
  # its flake.lock decides every input revision this machine runs.
  inputs.nixlypkgs.url = "github:aCeTotal/nixlypkgs/$CHANNEL";

  outputs = { nixlypkgs, ... }: {
    nixosConfigurations.nixlyos = nixlypkgs.lib.mkNixlySystem {
      hostName = "$HOSTNAME";
      username = "$NIXLY_USER";
      stateVersion = "$STATE_VERSION";
      hardwareDir = ./hardware;
      localConfig = ./local.nix;
    };
  };
}
FLAKE

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

# The default user is uid 1000; nixos-install runs before the user exists.
chown -R 1000:100 "/mnt/home/$NIXLY_USER"

log "Genererer Secure Boot-nøkler for lanzaboote"
nix-shell -p sbctl --run "sbctl create-keys --database-path /mnt/etc/secureboot --export /mnt/etc/secureboot"

log "Installing NixOS from flake $NIXLY_DIR#nixlyos (no root password)"
nixos-install --no-root-password --root /mnt --flake "$NIXLY_DIR#nixlyos"

log "Installation complete. Unmounting and closing LUKS."
umount -R /mnt || true
cryptsetup close cryptroot || true

log "Done. Reboot into your new system."
