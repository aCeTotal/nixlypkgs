#!/usr/bin/env bash
# Seeds ~/.local/nixlyos/custom/{inputs.nix,modules.nix} on first run, then
# regenerates the user-inputs block in the machine flake from inputs.nix.
# Flake inputs must be literal, so this is the only way user inputs can reach
# flake.nix. Reserved names are refused so a user input can never shadow one
# the system depends on.
set -euo pipefail

DIR=${1:-"$HOME/.local/nixlyos"}
FLAKE="$DIR/flake.nix"
CUSTOM="$DIR/custom"
[[ -f $FLAKE ]] || { echo "error: missing $FLAKE" >&2; exit 1; }

mkdir -p "$CUSTOM"

if [[ ! -f $CUSTOM/inputs.nix ]]; then
  cat > "$CUSTOM/inputs.nix" <<'SEED'
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
SEED
fi

# Keybindings live at the nixlyos root, NOT in custom/: nixlytile reads and
# inotify-watches ~/.local/nixlyos/bindings.conf directly, so an edit applies
# immediately without any rebuild. Seed the full default set on first run.
if [[ ! -f $DIR/bindings.conf && -n ${DEFAULT_BINDINGS:-} ]]; then
  cp --no-preserve=mode "$DEFAULT_BINDINGS" "$DIR/bindings.conf"
  echo "seeded $DIR/bindings.conf"
fi

if [[ ! -f $CUSTOM/modules.nix ]]; then
  cat > "$CUSTOM/modules.nix" <<'SEED'
# Your own NixOS module. Anything you would normally put in configuration.nix
# goes here: packages, services, imports of your own module files in custom/.
# Inputs declared in custom/inputs.nix arrive through the `inputs` argument.
# Options the NixlyOS core owns (display manager, portals, secure boot, ...)
# are fenced off and refuse to build if set here.
{ ... }:

{
}
SEED
fi

# The NixlyOS core owns these option namespaces — they carry the nixlytile
# session chain and system integrity. A text scan (comments stripped) is used
# instead of an eval-time guard: inspecting option definitions in nix forces
# otherwise-dead values and breaks eval. Anything that slips past this still
# hits the module system's own conflict errors, and a failed build rolls back.
protected='services\.displayManager|xdg\.portal|boot\.lanzaboote|security\.polkit|systemd\.suppressedSystemUnits'
hits=""
while IFS= read -r -d "" f; do
  h=$(sed 's/#.*//' "$f" | grep -nE "$protected" || true)
  if [[ -n $h ]]; then
    hits+=$(sed "s|^|  ${f#"$DIR"/}:|" <<<"$h")$'\n'
  fi
done < <(find "$CUSTOM" -name '*.nix' -print0)
if [[ -n $hits ]]; then
  {
    echo "error: custom/ touches options owned by the NixlyOS core:"
    printf '%s' "$hits"
    echo "These control the nixlytile session and cannot be set from custom/."
  } >&2
  exit 1
fi

json=$(nix eval --json --impure --expr "import $CUSTOM/inputs.nix") || {
  echo "error: custom/inputs.nix does not evaluate" >&2
  exit 1
}

reserved=" self nixlypkgs nixpkgs nixpkgs-unstable nixos-stable nixos-hardware home-manager chaotic lanzaboote totalvim mnw "
while IFS= read -r name; do
  [[ $reserved == *" $name "* ]] &&
    { echo "error: custom/inputs.nix: '$name' is reserved by NixlyOS" >&2; exit 1; }
  [[ $name =~ ^[a-zA-Z_][a-zA-Z0-9_-]*$ ]] ||
    { echo "error: custom/inputs.nix: invalid input name '$name'" >&2; exit 1; }
done < <(jq -r 'keys[]' <<<"$json")

block=$(jq -r 'to_entries[] | if (.value|type) == "string"
    then "    \(.key).url = \"\(.value)\";"
    else "    \(.key) = { url = \"\(.value.url)\";\(if .value.flake == false then " flake = false;" else "" end) };"
    end' <<<"$json")

grep -q '# BEGIN USER INPUTS' "$FLAKE" ||
  { echo "error: $FLAKE has no user-inputs markers" >&2; exit 1; }

new=$(awk -v block="$block" '
  /# BEGIN USER INPUTS/ { print; if (block != "") print block; skip = 1; next }
  /# END USER INPUTS/   { skip = 0 }
  !skip { print }
' "$FLAKE")

# Redirect, not mv, so owner and mode survive; only touch on real change so
# the flake fingerprint (and the staged build) stays valid.
if [[ "$new" != "$(<"$FLAKE")" ]]; then
  printf '%s\n' "$new" > "$FLAKE"
  echo "flake.nix: user inputs updated"
fi
