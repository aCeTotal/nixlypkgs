{ pkgs, hwData, ... }:

let
  # Cores, RAM and build parallelism for this machine, from scripts/detect-hw.sh.
  hw = hwData.resources;

  # Daily idle maintenance: only when the mouse has been idle 60 min
  # and no game runs, at most once per 24 h.  Replaces the weekly GC
  # timer; reads /dev/input/mice (byte = pointer motion) and runs
  # nix-gc plus the other cleanups that keep the machine fast: journal
  # vacuum, old coredumps, stale thumbnails, and an fstrim right after
  # GC so the SSD gets the freed blocks back while everything is idle.
  # Shader caches (mesa/nvidia) are deliberately never touched — they
  # prevent in-game stutter.
  gcWatch = pkgs.writeShellApplication {
    name = "nixly-gc-watch";
    runtimeInputs = with pkgs; [ coreutils findutils procps systemd util-linux ];
    text = ''
      stamp=/var/lib/nixly-gc-watch/last
      while :; do
        now=$(date +%s)
        if [ -f "$stamp" ]; then
          last=$(stat -c %Y "$stamp")
          left=$(( 86400 - (now - last) ))
          if [ "$left" -gt 0 ]; then
            sleep "$left"
            continue
          fi
        fi
        if [ ! -r /dev/input/mice ]; then
          sleep 3600
          continue
        fi
        # A byte within the window = motion; reset the idle counter.
        idle=0
        while [ "$idle" -lt 3600 ]; do
          if timeout 60 head -c1 /dev/input/mice >/dev/null 2>&1; then
            idle=0
          else
            idle=$((idle + 60))
          fi
        done
        if systemctl is-active -q nixly-gametune.service \
           || pgrep -x wineserver >/dev/null 2>&1 \
           || pgrep -x gamescope >/dev/null 2>&1 \
           || pgrep -x retroarch >/dev/null 2>&1 \
           || pgrep -x reaper >/dev/null 2>&1; then
          sleep 600
          continue
        fi
        systemctl start nix-gc.service
        # Age-trim the journal below the 200M size cap in journald.conf.
        journalctl --vacuum-time=14d >/dev/null 2>&1 || true
        # Old crash dumps are dead weight on disk.
        find /var/lib/systemd/coredump -type f -mtime +7 -delete 2>/dev/null || true
        # Stale thumbnail caches grow without bound.
        find /home/*/.cache/thumbnails -type f -mtime +30 -delete 2>/dev/null || true
        # Trash older than 30 days.  The .trashinfo mtime IS the
        # deletion time, so match on it rather than the file's own
        # (possibly much older) mtime, then drop both halves.
        for t in /home/*/.local/share/Trash; do
          [ -d "$t/info" ] || continue
          find "$t/info" -name '*.trashinfo' -mtime +30 2>/dev/null \
          | while IFS= read -r info; do
            name=$(basename "$info" .trashinfo)
            rm -rf -- "$t/files/$name" "$info" 2>/dev/null || true
          done
        done
        # Trim now: GC just freed the most blocks it will all day.
        fstrim -a >/dev/null 2>&1 || true
        touch "$stamp"
      done
    '';
  };
in
{
  nix = {
    package = pkgs.nixVersions.latest;

    settings = {
      # No auto-optimise-store: the weekly nix-optimise timer does the same job
      # without hardlinking synchronously during every build.
      sandbox = true;
      accept-flake-config = false;
      # detect-hw.sh writes generated files before each eval, so the tree is always dirty.
      warn-dirty = false;
      experimental-features = [ "nix-command" "flakes" ];
      keep-outputs = true;
      keep-derivations = true;
      builders-use-substitutes = true;
      # Scaled to RAM and cores: one job per 8 GiB, capped by both.
      max-jobs = hw.maxJobs;
      cores = hw.buildCores;
      http-connections = 50;
      # Low so an unreachable substituter never stalls builds; fallback
      # makes nix move on / build locally instead of waiting.
      connect-timeout = 5;
      fallback = true;
      min-free = 2147483648;
      max-free = 6442450944;
      trusted-users = [ "root" "@wheel" ];

      substituters = [
        # NixlyOS binary cache: prebuilt nixlypkgs packages for every main commit.
        "https://cache.aceclan.no"
        "https://cache.nixos.org"
        "https://attic.xuyh0120.win/lantian"
        # Prebuilt CachyOS kernel + nvidia module; without this they build from source.
        "https://nyx-cache.chaotic.cx/"
      ];

      trusted-substituters = [
        "https://cache.aceclan.no"
        "https://cache.nixos.org"
        "https://attic.xuyh0120.win/lantian"
        "https://nyx-cache.chaotic.cx/"
      ];

      trusted-public-keys = [
        "cache.aceclan.no-1:qfGAXabgsofKSAqId9sqqbPlQic4l7gOGeWPrqUg3ak="
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "lantian:EeAUQ+W+6r7EtwnmYjeVwx5kOGEBpjlBfPlzGlTNvHc="
        "nyx-cache.chaotic.cx:dJxTrgMC3V3cFfyIiBQDQorG6k1LsqurH/srpMSq7qk="
      ];
    };

    gc = {
      # No timer: nixly-gc-watch starts nix-gc.service after 60 min
      # mouse idle with no game running, max once per 24 h.  options
      # still feeds the service's nix-collect-garbage invocation.
      automatic = false;
      options = "--delete-older-than 3d";
    };

    optimise = {
      automatic = true;
      dates = [ "Sun 05:00" ];
      # Same reasoning as gc: no catch-up hashing of the whole store at boot.
      persistent = false;
    };
  };

  systemd.services.nixly-gc-watch = {
    description = "Run nix-gc after 60 min mouse idle without a game, max once a day";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${gcWatch}/bin/nixly-gc-watch";
      Restart = "on-failure";
      RestartSec = 60;
      StateDirectory = "nixly-gc-watch";
      Nice = 19;
      IOSchedulingClass = "idle";
    };
  };

  # GC and optimise run at idle priority so they never contend with foreground apps.
  systemd.services.nix-gc.serviceConfig = {
    CPUSchedulingPolicy = "idle";
    IOSchedulingClass = "idle";
    Nice = 19;
  };

  systemd.services.nix-optimise.serviceConfig = {
    CPUSchedulingPolicy = "idle";
    IOSchedulingClass = "idle";
    Nice = 19;
  };

  # Cgroup memory cap so a runaway build is killed instead of the desktop.
  systemd.services.nix-daemon.serviceConfig = {
    MemoryAccounting = true;
    MemoryHigh = "80%";
    MemoryMax = "90%";
    Delegate = "memory cpu io";
  };

  # fstrim: same reasoning, async at night and never replayed at boot.
  services.fstrim = {
    interval = "Sun 04:00";
  };
  systemd.timers.fstrim.timerConfig.Persistent = false;
}

