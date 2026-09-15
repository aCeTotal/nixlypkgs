# HTPC session: one app per workspace, all of them resident. The guide
# menu (nixlytile htpc_guide.c) switches workspace instead of killing —
# measured 2026-09-15, a Steam restart cost 9.2 s against one frame for a
# switch. It calls `htpc-start <app>` only when that workspace is empty
# (first use or after a crash), and `htpc-stop geforcenow` when leaving
# GeForce NOW, which cannot survive being frozen: NVIDIA drops the session.
#
# Each app gets its own supervisor loop, so quitting one brings it back
# exactly like the old single-app supervisor did.
{ pkgs, lib, config, ... }:

let
  shortcutsCleanup = pkgs.callPackage ./steam-shortcuts.nix { };

  htpcStart = pkgs.writeShellScriptBin "htpc-start" ''
    # Re-exec of self under setsid: the supervisor loop for one app, in
    # its own process group so htpc-stop can take the whole tree.
    if [ "$1" = __loop ]; then
      app="$2"
      loop=1
    else
      app="$1"
      loop=0
    fi

    launch() {
      case "$app" in
        steam)
          # Steam only reads shortcuts.vdf at startup: drop the old
          # per-app shortcuts before every launch so they cannot start
          # second instances. Best-effort, never blocks Big Picture.
          ${shortcutsCleanup}/bin/htpc-steam-shortcuts-cleanup 2>&1 \
            | ${pkgs.systemd}/bin/systemd-cat -t htpc-steam-shortcuts || true
          steam -tenfoot
          ;;
        geforcenow) nixly-gfn ;;
        nixlymedia) nixlymedia ;;
        *)          retroarch ;;
      esac
    }

    if [ "$loop" = 1 ]; then
      while :; do
        launch
        # A boot-looping app must not spin.
        sleep 0.3
      done
    fi

    run="''${XDG_RUNTIME_DIR:-/tmp}"
    pidfile="$run/htpc-app.$app.pid"

    # Already supervised: the guide only wants it on screen.
    if [ -s "$pidfile" ] && kill -0 "$(cat "$pidfile")" 2>/dev/null; then
      exit 0
    fi

    # RP1 for nixlymedia/GFN (VRM noise on eARC), full range for games.
    htpc-gpu-clock "$app" 2>/dev/null || true

    setsid "$0" __loop "$app" >/dev/null 2>&1 &
    printf %s $! > "$pidfile"
  '';

  htpcStop = pkgs.writeShellScriptBin "htpc-stop" ''
    app="$1"
    run="''${XDG_RUNTIME_DIR:-/tmp}"
    pidfile="$run/htpc-app.$app.pid"
    pid=$(cat "$pidfile" 2>/dev/null || true)
    rm -f "$pidfile"

    if [ "$app" = geforcenow ]; then
      # bwrap children may sit outside the group; flatpak knows them.
      ${pkgs.flatpak}/bin/flatpak kill com.nvidia.geforcenow 2>/dev/null || true
      ${pkgs.systemd}/bin/systemctl stop --no-block gfn-focus.service 2>/dev/null || true
    fi

    [ -n "$pid" ] || exit 0
    kill -TERM -- -"$pid" 2>/dev/null || true
    i=0
    while [ "$i" -lt 6 ]; do
      kill -0 -- -"$pid" 2>/dev/null || exit 0
      sleep 0.05
      i=$((i + 1))
    done
    kill -KILL -- -"$pid" 2>/dev/null || true
  '';

  htpcApp = pkgs.writeShellScriptBin "htpc-app" ''
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
      if ${pkgs.xrandr}/bin/xrandr 2>/dev/null | grep -q ' connected'; then
        break
      fi
      sleep 0.5
    done

    htpc-start nixlymedia
  '';
in
lib.mkIf (config.nixlyos.mode == "htpc") {
  environment.systemPackages = [ htpcApp htpcStart htpcStop shortcutsCleanup ];
}
