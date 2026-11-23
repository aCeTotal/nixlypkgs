# Machine side of the Nixly panel.
set -euo pipefail

FLAKE="${NIXLYOS_DIR:-$HOME/.local/nixlyos}"
PROFILE_FILE="$FLAKE/profile"
BRANCH_FILE="$FLAKE/branch"
SOURCE_PATTERN='^(github:[A-Za-z0-9._-]+/[A-Za-z0-9._-]+/[0-9a-f]{40}|git\+[a-z]+://[^"[:space:]]+\?rev=[0-9a-f]{40})$'
TREE_PATTERN='^/api/v1/trees/[0-9a-f]{64}\.tar\.gz$'
NAME_PATTERN='^[a-z0-9][a-z0-9-]{0,31}$'
BRANCH_PATTERN='^(stable|testing)$'

die() { echo "nixlyos-panel: $*" >&2; exit 1; }

fetch() { curl -fsS --max-time 30 --retry 3 --retry-delay 2 "$@"; }

usage() {
  cat >&2 <<'USAGE'
usage: nixlyos-panel <command>
  profiles                  list profiles and their branches
  flake <host> <user> <stateVersion> <profile>
                            write a panel-managed flake.nix
  pin [dir]                 lock flake.nix to the profile's release
  use <profile>             follow another profile from the next update
  branch [stable|testing]   show or switch the release branch
  moved                     exit 0 when a newer release exists
  adopt                     move a pre-panel machine under the panel
USAGE
  exit 2
}

profile() {
  local name
  name=$(<"$PROFILE_FILE") || die "no profile chosen ($PROFILE_FILE)"
  [[ $name =~ $NAME_PATTERN ]] || die "invalid profile name: $name"
  echo "$name"
}

# Stable unless chosen otherwise.
branch() {
  local name=stable
  [[ -f $BRANCH_FILE ]] && name=$(<"$BRANCH_FILE")
  [[ $name =~ $BRANCH_PATTERN ]] || die "invalid branch: $name"
  echo "$name"
}

cmd_profiles() {
  fetch "$NIXLY_PANEL/api/v1/profiles" | jq -r '.[]
    | [(if .stable then "stable" else empty end), (if .testing then "testing" else empty end)] as $branches
    | select($branches | length > 0) | [.name, .title, .platform, ($branches | join(",")), .description] | @tsv'
}

# Writes, pins, then swaps in.
cmd_flake() {
  local host=${1:?host} user=${2:?user} version=${3:?stateVersion} name=${4:?profile}
  local inputs=""
  [[ $name =~ $NAME_PATTERN ]] || die "invalid profile name: $name"
  trap 'rm -f "$FLAKE/flake.nix.tmp" "$PROFILE_FILE.tmp"' EXIT
  [[ -f "$FLAKE/flake.nix" ]] && inputs=$(awk '/# END USER INPUTS/ { skip = 0 } skip { print } /# BEGIN USER INPUTS/ { skip = 1 }' "$FLAKE/flake.nix")
  cat > "$FLAKE/flake.nix.tmp" <<FLAKE
{
  description = "NixlyOS machine";

  inputs = {
    # Both pinned by nixlyos-panel.
    nixlypkgs.url = "github:aCeTotal/nixlypkgs";
    nixlyprofile = { url = "$NIXLY_PANEL/api/v1/profiles"; flake = false; };
    # BEGIN USER INPUTS (generated from custom/inputs.nix — edit that instead)
${inputs}
    # END USER INPUTS
  };

  outputs = inputs@{ nixlypkgs, nixlyprofile, ... }: {
    nixosConfigurations.nixlyos = nixlypkgs.lib.mkNixlySystem {
      hostName = "$host";
      username = "$user";
      stateVersion = "$version";
      hardwareDir = ./hardware;
      localConfig = ./local.nix;
      userModules = ./custom/modules.nix;
      userInputs = builtins.removeAttrs inputs [ "nixlypkgs" "nixlyprofile" "self" ];
      profileTree = nixlyprofile;
    };
  };
}
FLAKE
  echo "$name" > "$PROFILE_FILE.tmp"
  pin_file "$FLAKE/flake.nix.tmp" "$name"
  mv "$PROFILE_FILE.tmp" "$PROFILE_FILE"
  mv "$FLAKE/flake.nix.tmp" "$FLAKE/flake.nix"
}

release() {
  fetch "$NIXLY_PANEL/api/v1/profiles/$1/$(branch)"
}

pin_file() {
  local file=$1 pointer source path
  pointer=$(release "$2")
  source=$(jq -r .source <<< "$pointer")
  path=$(jq -r .path <<< "$pointer")
  [[ $source =~ $SOURCE_PATTERN && $path =~ $TREE_PATTERN ]] || die "unexpected release: $pointer"
  sed -i -E \
    -e "s|^([[:space:]]*nixlypkgs\.url = )\"[^\"]*\";|\1\"$source\";|" \
    -e "s|^([[:space:]]*nixlyprofile = \{ url = )\"[^\"]*\";|\1\"$NIXLY_PANEL$path\";|" \
    "$file"
}

cmd_pin() {
  local file=${1:-$FLAKE}/flake.nix
  cp "$file" "$file.tmp"
  pin_file "$file.tmp" "$(profile)"
  mv "$file.tmp" "$file"
}

cmd_moved() {
  local pointer
  pointer=$(release "$(profile)") || return 1
  ! grep -qF "\"$(jq -r .source <<< "$pointer")\"" "$FLAKE/flake.nix" ||
    ! grep -qF "$(jq -r .path <<< "$pointer")\"" "$FLAKE/flake.nix"
}

cmd_use() {
  local name=${1:?profile}
  [[ $name =~ $NAME_PATTERN ]] || die "invalid profile name: $name"
  release "$name" > /dev/null || die "no $(branch) release of profile: $name"
  echo "$name" > "$PROFILE_FILE"
}

cmd_branch() {
  [[ $# -eq 0 ]] && { branch; return; }
  [[ $1 =~ $BRANCH_PATTERN ]] || die "branch must be stable or testing: $1"
  fetch "$NIXLY_PANEL/api/v1/profiles/$(profile)/$1" > /dev/null || die "no $1 release of profile: $(profile)"
  echo "$1" > "$BRANCH_FILE"
}

# Picks the profile today's setup matches.
cmd_adopt() {
  [[ -f $PROFILE_FILE ]] && return 0
  local name=desktop host user version
  [[ $(cat /etc/nixlyos-mode 2>/dev/null) == htpc ]] && name=htpc
  host=$(grep -oP 'hostName = "\K[^"]+' "$FLAKE/flake.nix") || die "no hostName in flake.nix"
  user=$(grep -oP 'username = "\K[^"]+' "$FLAKE/flake.nix") || die "no username in flake.nix"
  version=$(grep -oP 'stateVersion = "\K[^"]+' "$FLAKE/flake.nix") || die "no stateVersion in flake.nix"
  release "$name" > /dev/null
  cp "$FLAKE/flake.nix" "$FLAKE/flake.nix.pre-panel"
  cmd_flake "$host" "$user" "$version" "$name"
}

command=${1:-}
shift || :
case $command in
  profiles) cmd_profiles ;;
  flake) cmd_flake "$@" ;;
  pin) cmd_pin "$@" ;;
  use) cmd_use "$@" ;;
  branch) cmd_branch "$@" ;;
  moved) cmd_moved ;;
  adopt) cmd_adopt ;;
  *) usage ;;
esac
