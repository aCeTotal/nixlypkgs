{ writeShellApplication, git, coreutils }:

writeShellApplication {
  name = "cachepanel-demo-repo";
  runtimeInputs = [ git coreutils ];
  text = ''
    # Usage: <dir> [init|bump]
    dir=$1
    export GIT_AUTHOR_NAME="Nixly Demo" GIT_AUTHOR_EMAIL=demo@nixly.invalid
    export GIT_COMMITTER_NAME="$GIT_AUTHOR_NAME" GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"

    commit() {
      echo "$1" > "$dir/revision"
      git -C "$dir" add --all
      git -C "$dir" commit --quiet -m "Demo-revisjon $1"
    }

    # Empty modules under the slugs the seeded profiles choose.
    modules() {
      mkdir -p "$dir/nixlyos/modules"
      entries=""
      for slug in system security network session audio user gaming apps desktop htpc server hardware; do
        echo '{ ... }: { }' > "$dir/nixlyos/modules/$slug.nix"
        case $slug in system | security | network | user | hardware) required=true ;; *) required=false ;; esac
        entries+="''${entries:+,}{\"slug\":\"$slug\",\"title\":\"$slug\",\"description\":\"\",\"required\":$required}"
      done
      echo "[$entries]" > "$dir/nixlyos/modules/catalogue.json"
    }

    # The seeded profiles, as the source keeps them.
    profiles() {
      mkdir -p "$dir/nixlyos/profiles"
      while read -r name title platform modules; do
        printf '{"title":"%s","description":"","platform":"%s","kernel":"performance","kernelSettings":{},"pinnedSha":null,"modules":%s,"packages":[]}\n' \
          "$title" "$platform" "$modules" > "$dir/nixlyos/profiles/$name.json"
      done <<EOF
    desktop Desktop desktop ["apps","audio","desktop","gaming","session"]
    htpc HTPC htpc ["apps","audio","gaming","htpc","session"]
    server Server server ["server"]
    EOF
    }

    case "''${2:-init}" in
      init)
        [ -d "$dir/.git" ] && exit 0
        mkdir -p "$dir"
        install -m 0644 ${./demo-flake.nix} "$dir/flake.nix"
        git -C "$dir" init --quiet --initial-branch=main
        modules
        profiles
        for revision in 1 2 3 4; do commit "$revision"; done
        ;;
      bump)
        commit $(( $(cat "$dir/revision") + 1 ))
        ;;
    esac
  '';
}
