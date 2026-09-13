# HTPC session: ONE app at a time on one workspace. nixlytile starts
# htpc-app from its autostart list (home/nixlytile.nix); it launches the
# current app — RetroArch at boot — and relaunches it on crash or user
# quit. The guide menu (nixlytile htpc_guide.c) runs `htpc-switch <app>`,
# which records the new app and kills the running one's process group;
# the supervisor then starts the new app immediately.
{ pkgs, lib, config, ... }:

let
  shortcutsCleanup = pkgs.callPackage ./steam-shortcuts.nix { };

  htpcApp = pkgs.writeShellScriptBin "htpc-app" ''
    state="''${XDG_RUNTIME_DIR:-/tmp}/htpc-app"
    [ -s "$state" ] || printf retroarch > "$state"

    # Boot readiness gate: htpc-app autostarts in parallel with
    # xwayland-satellite and the TV's HDMI mode-set.  The FIRST app
    # launched before X/:0 answers (or before the output is configured)
    # picks a different video path than every later launch — RetroArch
    # auto-selects its video driver from what it finds at startup, so
    # the boot instance ran degraded until it was toggled away and back.
    # Wait until xrandr sees a connected output (proves both satellite
    # and the compositor output are up), bounded so a broken X never
    # blocks the session.
    export DISPLAY="''${DISPLAY:-:0}"
    for _ in $(seq 30); do
      if ${pkgs.xorg.xrandr}/bin/xrandr 2>/dev/null | grep -q ' connected'; then
        break
      fi
      sleep 0.5
    done

    while :; do
      app=$(cat "$state")
      case "$app" in
        steam)
          # Steam only reads shortcuts.vdf at startup: drop the old
          # per-app shortcuts before every launch so they cannot start
          # second instances. Best-effort, never blocks Big Picture.
          ${shortcutsCleanup}/bin/htpc-steam-shortcuts-cleanup 2>&1 \
            | ${pkgs.systemd}/bin/systemd-cat -t htpc-steam-shortcuts || true
          setsid steam -tenfoot &
          ;;
        geforcenow)
          # --password-store=basic: the CEF client otherwise asks the
          # keyring for a master password on a box that autologs in
          # without one.
          setsid flatpak run com.nvidia.geforcenow --password-store=basic &
          ;;
        nixlymedia)
          setsid nixlymedia &
          ;;
        *)
          setsid retroarch &
          ;;
      esac
      printf %s $! > "$state.pid"
      wait $!
      rm -f "$state.pid"
      # Crash/quit of the same app: brief pause so a boot-looping app
      # cannot spin. A switch (state changed) starts instantly.
      [ "$(cat "$state")" = "$app" ] && sleep 0.3
    done
  '';

  # htpc-switch <steam|retroarch|geforcenow|nixlymedia> — called by the
  # nixlytile guide menu. setsid above made the app a session/process
  # group leader, so killing -pid takes its whole tree; the supervisor's
  # wait returns the moment the leader dies and the new app starts while
  # stragglers get the delayed KILL.
  htpcSwitch = pkgs.writeShellScriptBin "htpc-switch" ''
    app="$1"
    state="''${XDG_RUNTIME_DIR:-/tmp}/htpc-app"
    cur=$(cat "$state" 2>/dev/null || true)
    [ "$app" = "$cur" ] && exit 0
    printf %s "$app" > "$state"
    pid=$(cat "$state.pid" 2>/dev/null || true)
    [ -n "$pid" ] || exit 0
    kill -TERM -- -"$pid" 2>/dev/null || true
    if [ "$cur" = geforcenow ]; then
      # bwrap children may sit outside the group; flatpak knows them.
      ${pkgs.flatpak}/bin/flatpak kill com.nvidia.geforcenow 2>/dev/null || true
    fi
    for _ in $(seq 20); do
      kill -0 -- -"$pid" 2>/dev/null || exit 0
      sleep 0.1
    done
    kill -KILL -- -"$pid" 2>/dev/null || true
  '';
in
lib.mkIf (config.nixlyos.mode == "htpc") {
  environment.systemPackages = [ htpcApp htpcSwitch shortcutsCleanup ];
}
