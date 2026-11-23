# Firmware keys follow the panel's CA.
set -euo pipefail

CA=/run/current-system/nixlyos-ca.pem
GLOBAL=8be4df61-93ca-11d2-aa0d-00e098032b8c
EFIVARS=/sys/firmware/efi/efivars

die() { echo "nixlyos-secureboot: $*" >&2; exit 1; }

usage() {
  cat >&2 <<'USAGE'
usage: nixlyos-secureboot <command>
  status    firmware keys and whether they follow the panel
  enroll    firmware in setup mode: take the panel's PK, KEK and db
  update    after a CA rotation: move the keys to the new CA
USAGE
  exit 2
}

# Last byte of an EFI variable.
flag() { od -An -tu1 -j4 "$EFIVARS/$1-$GLOBAL" 2>/dev/null | tr -d ' '; }

# Fingerprint of the enrolled platform key.
platform_key() {
  efi-readvar -v PK -o "$WORK/pk.esl" > /dev/null
  sig-list-to-certs "$WORK/pk.esl" "$WORK/pk" > /dev/null 2>&1 || return 0
  sha256sum "$WORK/pk-0.der" | cut -d' ' -f1
}

ours() { openssl x509 -in "$CA" -outform DER | sha256sum | cut -d' ' -f1; }

fetch_keys() {
  local from=$1 variable
  for variable in PK KEK db; do
    curl -fsS --max-time 30 --retry 3 -o "$WORK/$variable.auth" "$NIXLY_PANEL/api/v1/secureboot/$from/$variable.auth" \
      || die "the panel has no key update from $from"
  done
}

# Firmware verifies each write in order.
write_keys() {
  local variable
  for variable in "$@"; do
    efi-updatevar -f "$WORK/$variable.auth" "$variable" || die "firmware refused $variable"
  done
}

cmd_status() {
  local enrolled
  enrolled=$(platform_key)
  echo "Secure Boot:  $([ "$(flag SecureBoot)" = 1 ] && echo on || echo off)"
  echo "Setup mode:   $([ "$(flag SetupMode)" = 1 ] && echo yes || echo no)"
  echo "Platform key: ${enrolled:-none}"
  echo "NixlyOS CA:   $(ours)"
  if [ "$enrolled" = "$(ours)" ]; then echo "Firmware follows the panel."; return; fi
  [ -n "$enrolled" ] && echo "Run 'nixlyos-secureboot update' to move to this CA." && return
  echo "Clear the keys in the firmware setup, then run 'nixlyos-secureboot enroll'."
}

cmd_enroll() {
  [ "$(id -u)" = 0 ] || die "run as root"
  [ "$(flag SetupMode)" = 1 ] || die "firmware is not in setup mode; clear its Secure Boot keys first"
  fetch_keys setup
  openssl x509 -in "$CA" -outform DER -out "$WORK/ca.der"
  # Only the PK is trusted unchecked.
  tail -c "$(stat -c %s "$WORK/ca.der")" "$WORK/PK.auth" | cmp -s - "$WORK/ca.der" || die "the panel's PK is not this system's CA"
  write_keys PK KEK db
  echo "Enrolled. Turn Secure Boot on in the firmware setup."
}

cmd_update() {
  [ "$(id -u)" = 0 ] || die "run as root"
  local enrolled
  enrolled=$(platform_key)
  [ -n "$enrolled" ] || die "no platform key; use enroll"
  [ "$enrolled" != "$(ours)" ] || { echo "Firmware already follows the panel."; return; }
  fetch_keys "$enrolled"
  write_keys db KEK PK
  echo "Firmware keys moved to the current NixlyOS CA."
}

[ -r "$CA" ] || die "this system carries no NixlyOS CA"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
case "${1:-status}" in
  status) cmd_status ;;
  enroll) cmd_enroll ;;
  update) cmd_update ;;
  *) usage ;;
esac
