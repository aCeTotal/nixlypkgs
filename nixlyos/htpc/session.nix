# HTPC session: one app at a time on one workspace. The guide menu
# (nixlytile htpc_guide.c) calls `htpc-switch <app>`, which SIGKILLs every
# running app through cgroup.kill and starts the new one without waiting.
{ pkgs, lib, config, ... }:

let
  shortcutsCleanup = pkgs.callPackage ./steam-shortcuts.nix { };

  # Supervisor: restarts the app on exit.
  htpcLoop = pkgs.writeShellScript "htpc-loop" ''
    app="$1"
    while :; do
      case "$app" in
        steam)
          # Stale shortcuts spawn second instances.
          ${shortcutsCleanup}/bin/htpc-steam-shortcuts-cleanup 2>&1 \
            | ${pkgs.systemd}/bin/systemd-cat -t htpc-steam-shortcuts || true
          steam -tenfoot
          ;;
        geforcenow) nixly-gfn ;;
        nixlymedia) nixlymedia ;;
        *)          retroarch ;;
      esac
      # A boot-looping app must not spin.
      sleep 0.3
    done
  '';

  htpcSwitch = pkgs.writeShellScriptBin "htpc-switch" ''
    app="$1"
    uid=$(${pkgs.coreutils}/bin/id -u)
    cg=/sys/fs/cgroup/user.slice/user-$uid.slice/user@$uid.service

    for kill in "$cg"/app.slice/htpc-app-*.scope/cgroup.kill \
                "$cg"/app.slice/app-flatpak-com.nvidia.geforcenow-*.scope/cgroup.kill; do
      [ -e "$kill" ] && echo 1 > "$kill"
    done

    # GFN runs outside our scope.
    if grep -q '^populated 1' "$cg/gfn.slice/cgroup.events" 2>/dev/null; then
      echo 1 > "$cg/gfn.slice/cgroup.kill"
      ${pkgs.systemd}/bin/systemctl stop --no-block gfn-focus.service 2>/dev/null || true
    fi

    # RP1 for nixlymedia/GFN (VRM noise on eARC), full range for games.
    htpc-gpu-clock "$app" 2>/dev/null || true

    exec ${pkgs.systemd}/bin/systemd-run --user --scope --quiet --collect \
      --slice=app.slice --unit="htpc-app-$app-$$" -- ${htpcLoop} "$app"
  '';

  htpcApp = pkgs.writeShellScriptBin "htpc-app" ''
    # Wait for X and output.
    export DISPLAY="''${DISPLAY:-:0}"
    for _ in $(seq 30); do
      if ${pkgs.xrandr}/bin/xrandr 2>/dev/null | grep -q ' connected'; then
        break
      fi
      sleep 0.5
    done

    exec htpc-switch nixlymedia
  '';
in
lib.mkIf (config.nixlyos.mode == "htpc") {
  environment.systemPackages = [ htpcApp htpcSwitch shortcutsCleanup ];
}
