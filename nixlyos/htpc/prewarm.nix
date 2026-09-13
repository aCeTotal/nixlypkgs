# Keep RetroArch, nixlymedia and GeForce NOW resident in RAM so they open
# instantly from Big Picture. vmtouch -t pulls every file of their closures
# into the page cache; the 10-minute re-touch keeps the pages young in the
# LRU so normal memory pressure does not evict them. Never runs while a
# game is active — the desktop prewarm gate philosophy carried over.
{ pkgs, lib, config, ... }:

let
  raFull = import ./retroarch-full.nix { inherit pkgs; };

  # Full runtime closures, one store path per line, resolved at build time.
  closure = pkgs.writeClosure [
    raFull
    pkgs.nixlymedia
    pkgs.retroarch-assets
    pkgs.libretro-shaders-slang
  ];

  warmScript = pkgs.writeShellScript "htpc-prewarm" ''
    set -u
    VMTOUCH=${pkgs.vmtouch}/bin/vmtouch

    # A running game owns RAM and IO; touching gigabytes now would only
    # cause eviction pressure and disk noise.
    ${pkgs.systemd}/bin/systemctl is-active -q nixly-gametune.service && exit 0
    ${pkgs.procps}/bin/pgrep -x wineserver >/dev/null 2>&1 && exit 0
    ${pkgs.procps}/bin/pgrep -x gamescope  >/dev/null 2>&1 && exit 0

    warm() {
      [ -e "$1" ] && "$VMTOUCH" -t -q -m 512M "$1" 2>/dev/null || true
    }

    while IFS= read -r p; do
      warm "$p"
    done < ${closure}

    # GeForce NOW runs as a flatpak: the app itself plus the runtime it
    # actually links against live outside the nix store.
    warm /var/lib/flatpak/app/com.nvidia.geforcenow
    rt=$(${pkgs.flatpak}/bin/flatpak info --show-runtime com.nvidia.geforcenow 2>/dev/null || true)
    rt=''${rt#runtime/}
    [ -n "$rt" ] && warm "/var/lib/flatpak/runtime/$rt"
    exit 0
  '';
  # Boot-time warm of ONLY the app that is on screen at boot (the
  # supervisor starts RetroArch): its closure demand-pages off a cold
  # disk for the first minutes otherwise, since the full prewarm timer
  # deliberately waits 3 min.  Sequential vmtouch readahead of exactly
  # these paths is strictly faster than the app faulting them in one
  # page at a time, so this cannot make the cold start worse.
  firstWarmScript = pkgs.writeShellScript "htpc-prewarm-first" ''
    set -u
    VMTOUCH=${pkgs.vmtouch}/bin/vmtouch
    while IFS= read -r p; do
      [ -e "$p" ] && "$VMTOUCH" -t -q -m 512M "$p" 2>/dev/null || true
    done < ${closure}
    exit 0
  '';
in
lib.mkIf (config.nixlyos.mode == "htpc") {

  systemd.services.htpc-prewarm-first = {
    description = "Warm the boot HTPC app (RetroArch/nixlymedia) at startup";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${firstWarmScript}";
      Nice = 19;
      CPUSchedulingPolicy = "idle";
      IOSchedulingClass = "idle";
      MemoryHigh = "8G";
    };
  };

  systemd.services.htpc-prewarm = {
    description = "Keep HTPC apps (RetroArch/nixlymedia/GeForce NOW) in RAM";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${warmScript}";
      Nice = 19;
      CPUSchedulingPolicy = "idle";
      IOSchedulingClass = "idle";
      # The kernel reclaims prewarm's own pages before the session's.
      MemoryHigh = "8G";
    };
  };

  systemd.timers.htpc-prewarm = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      # 3min, not 45s: the first vmtouch pass pulls gigabytes off disk and
      # collides with Steam's cold start (idle IO class is a no-op on
      # NVMe's `none` scheduler). Big Picture gets the disk to itself
      # first; prewarm catches up right after.
      OnBootSec = "3min";
      OnUnitActiveSec = "10min";
      Persistent = false;
    };
  };
}
