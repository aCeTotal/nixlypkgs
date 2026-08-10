#!/usr/bin/env bash
# Launch wfica with seamless windows disabled.
#
# StoreFront ships .ica files with TWIMode=On, which overrides the TWIMode=0
# defaults in wfclient.ini/All_Regions.ini/module.ini. Under a tiling
# compositor each seamless popup becomes its own tile, so menus and dialogs
# are unusable. Rewrite the setting into a private copy before launching.
set -u
export PATH=@coreutils@:@gnused@:@gnugrep@:$PATH

args=()
for arg in "$@"; do
  if [[ "$arg" == *.ica && -f "$arg" ]]; then
    tmp=$(mktemp --tmpdir="${XDG_RUNTIME_DIR:-/tmp}" --suffix=.ica wfica-XXXXXX)
    chmod 600 "$tmp"
    sed 's/^TWIMode=On/TWIMode=Off/I' "$arg" > "$tmp"
    grep -qi '^RemoveICAFile=yes' "$arg" && rm -f "$arg"
    args+=("$tmp")
  else
    args+=("$arg")
  fi
done

exec @wfica@ "${args[@]}"
