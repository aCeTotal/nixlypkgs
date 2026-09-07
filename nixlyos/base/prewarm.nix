{ pkgs, hwData, ... }:

let
  # Same variant pick as apps/steam/default.nix: the tool autoconfig defaults to.
  protonNixlyos =
    if hwData.resources.cpuLevel >= 3
    then pkgs.proton-nixlyos
    else pkgs.proton-nixlyos-generic;
  # Skip prewarm (exit 1) when a game runs or the box is busy.
  prewarmGate = pkgs.writeShellScript "nixly-prewarm-gate" ''
    set -u
    # Game active?
    if ${pkgs.systemd}/bin/systemctl is-active -q nixly-gametune.service; then
      exit 1
    fi
    if ${pkgs.procps}/bin/pgrep -x gamemoded >/dev/null 2>&1; then
      clients=$(${pkgs.systemd}/bin/busctl --user get-property \
        com.feralinteractive.GameMode /com/feralinteractive/GameMode \
        com.feralinteractive.GameMode ClientCount 2>/dev/null \
        | ${pkgs.gawk}/bin/awk '{print $2}')
      [ "''${clients:-0}" -gt 0 ] && exit 1
    fi
    # Non-Steam launches that neither gametune nor gamemoded sees:
    # wine/Proton outside Steam (Lutris, Heroic) and libretro.
    ${pkgs.procps}/bin/pgrep -x wineserver >/dev/null 2>&1 && exit 1
    ${pkgs.procps}/bin/pgrep -x retroarch >/dev/null 2>&1 && exit 1
    ${pkgs.procps}/bin/pgrep -x gamescope >/dev/null 2>&1 && exit 1
    ${pkgs.procps}/bin/pgrep -x reaper >/dev/null 2>&1 && exit 1
    # Busy? 1-min load over half the cores means something heavy runs.
    ncpu=$(${pkgs.coreutils}/bin/nproc)
    ${pkgs.gawk}/bin/awk -v n="$ncpu" '{exit ($1 > n/2) ? 1 : 0}' /proc/loadavg \
      || exit 1
    # Memory pressure? Under 25 % free the warmed pages just get evicted.
    ${pkgs.gawk}/bin/awk '/MemTotal/{t=$2} /MemAvailable/{a=$2}
      END{exit (a < t/4) ? 1 : 0}' /proc/meminfo || exit 1
    exit 0
  '';

  # Warm the launch chain plus every installed game in every Steam library.
  prewarmGamesScript = pkgs.writeShellScript "nixly-prewarm-games" ''
    set -u
    VMTOUCH=${pkgs.vmtouch}/bin/vmtouch

    warm() {
      [ -e "$1" ] && "$VMTOUCH" -t -q -m 512M "$1" 2>/dev/null || true
    }

    S="$HOME/.local/share/Steam"
    [ -d "$S" ] || S="$HOME/.steam/steam"
    [ -d "$S" ] || exit 0

    # Every library folder from libraryfolders.vdf plus the main one.
    libs="$S"
    vdf="$S/steamapps/libraryfolders.vdf"
    if [ -f "$vdf" ]; then
      extra=$(${pkgs.gnugrep}/bin/grep -oP '"path"\s+"\K[^"]+' "$vdf" 2>/dev/null || true)
      libs=$(printf '%s\n%s\n' "$libs" "$extra" | ${pkgs.coreutils}/bin/sort -u)
    fi

    # Only the two most recently played games — nothing else.  The old
    # full-library sweep is gone on purpose: prewarm must never fill RAM
    # with games that aren't being played (directive Aug 2026: fresh
    # boots stay lean, only the two last games get warmed).
    manifests() {
      for lib in $libs; do
        for m in "$lib"/steamapps/appmanifest_*.acf; do
          [ -f "$m" ] || continue
          ${pkgs.gawk}/bin/awk -F'"' -v lib="$lib" '
            /"installdir"/  { d = $4 }
            /"LastPlayed"/  { p = $4 }
            END {
              if (d != "" && d !~ /^(Proton|SteamLinuxRuntime|Steamworks)/)
                printf "%d|%s/steamapps/common/%s\n", p, lib, d
            }' "$m"
        done
      done
    }

    played=$(manifests | ${pkgs.coreutils}/bin/sort -t'|' -k1,1 -rn \
      | ${pkgs.gawk}/bin/awk -F'|' '$1 > 0 { print $2 }' | ${pkgs.coreutils}/bin/head -2)
    # Here-string, not a pipe: a subshell would swallow the gate's exit.
    while IFS= read -r d; do
      [ -n "$d" ] || continue
      ${prewarmGate} || exit 0
      warm "$d"
    done <<< "$played"
  '';


  # Pull launch-critical files into page cache at login, at IO/CPU idle priority.
  pagecacheScript = pkgs.writeShellScript "nixly-pagecache" ''
    set -u
    VMTOUCH=${pkgs.vmtouch}/bin/vmtouch

    # -m 512M skips huge paks; they stream during the loading screen anyway.
    warm() {
      [ -e "$1" ] && "$VMTOUCH" -t -q -m 512M "$1" 2>/dev/null || true
    }

    # Steam launch chain: client, pressure-vessel runtime, Proton.
    S="$HOME/.local/share/Steam"
    [ -d "$S" ] || S="$HOME/.steam/steam"
    if [ -d "$S" ]; then
      warm "$S/ubuntu12_32"
      warm "$S/ubuntu12_64"
      warm "$S/linux32"
      warm "$S/linux64"
      warm "$S/config"
      for d in "$S"/steamapps/common/SteamLinuxRuntime*; do
        warm "$d"
      done
      # proton-nixlyos from the store, the one autoconfig picks.
      warm "${protonNixlyos}"
      for d in "$S"/steamapps/common/Proton*; do
        warm "$d"
      done
      # Warm shader caches avoid recompilation on launch.
      warm "$S/steamapps/shadercache"
    fi
    warm "$HOME/.cache/mesa_shader_cache"
    warm "$HOME/.cache/mesa_shader_cache_db"
    warm "$HOME/.cache/nvidia/GLCache"
    warm "$HOME/.nv/GLCache"
  '';

  # Runs as a compositor autostart.  Steam is never started from here —
  # the user starts it themselves.  Once Steam is running AND the mouse
  # has been idle for 10 minutes (/dev/input/mice delivers a byte on any
  # pointer motion, so a silent window = no motion), the two last played
  # games get warmed.  Any mouse motion during the warm aborts it.
  activityPrewarm = pkgs.writeShellApplication {
    name = "nixly-activity-prewarm";
    runtimeInputs = with pkgs; [ coreutils procps systemd ];
    text = ''
      need=600
      step=10
      while :; do
        # Steam must already be running; never started from here.
        if ! pgrep -x steam >/dev/null 2>&1; then
          sleep 60
          continue
        fi
        if [ ! -r /dev/input/mice ]; then
          # No pointer node: idleness can't be measured, so never warm.
          sleep 600
          continue
        fi
        # A byte within the window = motion; reset the idle counter.
        idle=0
        while [ "$idle" -lt "$need" ]; do
          if timeout "$step" head -c1 /dev/input/mice >/dev/null 2>&1; then
            idle=0
          else
            idle=$((idle + step))
          fi
        done
        pgrep -x steam >/dev/null 2>&1 || continue
        systemctl --user start nixly-prewarm-games.service &
        spid=$!
        aborted=0
        while kill -0 "$spid" 2>/dev/null; do
          if timeout "$step" head -c1 /dev/input/mice >/dev/null 2>&1; then
            aborted=1
            systemctl --user stop nixly-prewarm-games.service
            break
          fi
        done
        wait "$spid" 2>/dev/null || true
        # Completed untouched: done for this session.  Aborted: go back
        # to waiting for the next 10 min idle stretch.
        if [ "$aborted" -eq 0 ]; then
          exit 0
        fi
      done
    '';
  };

  # Replays downloaded Vulkan pipeline caches into the driver caches, and provides
  # the `readahead <appid>` the compositor calls on Play.
  prewarm = pkgs.writeShellApplication {
    name = "nixly-prewarm";
    runtimeInputs = with pkgs; [
      coreutils
      findutils
      gawk
      gnugrep
      inotify-tools
      procps
      util-linux
      vulkan-tools
    ];
    text = builtins.readFile ./nixly-prewarm;
  };
in
{
  # steam-run gives fossilize_replay its FHS env; prewarm must sit on system PATH.
  environment.systemPackages = [
    prewarm
    activityPrewarm
    pkgs.steam-run
    pkgs.vmtouch
  ];

  # Started by nixly-activity-prewarm once Steam runs and the mouse has
  # been idle 10 min — never at boot/login (fresh sessions stay at
  # minimal RAM).  Warms the Steam launch chain plus the two last
  # played games.
  systemd.user.services.nixly-prewarm-games = {
    description = "Preload Steam launch chain and the two last played games";
    serviceConfig = {
      Type = "oneshot";
      ExecCondition = "${prewarmGate}";
      ExecStart = [ "${pagecacheScript}" "${prewarmGamesScript}" ];
      IOSchedulingClass = "idle";
      CPUSchedulingPolicy = "idle";
      Nice = 19;
      # Cap so the kernel reclaims prewarm's own pages instead of the session's.
      MemoryHigh = "8G";
    };
  };

  # Full shader-replay pass; the script SIGSTOPs fossilize itself when a game starts.
  systemd.user.services.nixly-prewarm = {
    description = "nixlytile Steam shader prewarm";
    serviceConfig = {
      Type = "oneshot";
      ExecCondition = "${prewarmGate}";
      ExecStart = "${prewarm}/bin/nixly-prewarm run";
      Nice = 19;
      IOSchedulingClass = "idle";
      CPUSchedulingPolicy = "batch";
    };
    # fossilize_replay via steam-run and vendor Vulkan ICDs.
    path = [ "/run/current-system/sw" ];
  };

  # inotify on each library's shadercache; replays new pipeline caches as they land.
  systemd.user.services.nixly-prewarm-watch = {
    description = "nixlytile Steam shader prewarm install watcher";
    wantedBy = [ "default.target" ];
    serviceConfig = {
      ExecStart = "${prewarm}/bin/nixly-prewarm watch";
      Restart = "on-failure";
      RestartSec = 30;
      Nice = 19;
      IOSchedulingClass = "idle";
      CPUSchedulingPolicy = "batch";
    };
    path = [ "/run/current-system/sw" ];
  };
}
