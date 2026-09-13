# PS2 ISOs are 2-7 GB and live on the NFS share, and PCSX2 streams the disc
# image for the whole session instead of loading it once. Every miss is a
# round trip to 10.0.0.8, so a fresh launch runs well under full speed until
# enough of the game's working set has drifted into the page cache — the
# "slow for the first minute, then fine" that only PS2 shows, because every
# other system's ROMs are small enough to land in cache on the first read.
#
# Pulling the open ROM in with one sequential pass costs ~45 s for a 3.7 GB
# ISO at the link's 84 MB/s, and it runs ahead of the emulator instead of
# behind it: the game stops waiting on the network within seconds rather
# than minutes. The same pass fills the local fscache (base/nfs.nix mounts
# with fsc), so the next launch of that game never touches the network.
{ pkgs, lib, config, ... }:

lib.mkIf (config.nixlyos.mode == "htpc") {
  systemd.services.htpc-rom-cache = {
    description = "Pull the ROM the emulator has open into RAM";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "simple";
      Restart = "always";
      RestartSec = 5;
      # vmtouch is the only CPU cost and it is trivial; the reads must run
      # at normal IO priority or they finish after the ramp they exist to
      # remove.
      Nice = 5;
      ExecStart = pkgs.writeShellScript "htpc-rom-cache" ''
        set -u
        warmed=""

        while :; do
          for pid in $(${pkgs.procps}/bin/pgrep -f retroarch); do
            for fd in /proc/$pid/fd/*; do
              rom=$(readlink "$fd" 2>/dev/null) || continue
              case "$rom" in
                /mnt/nfs/*) ;;
                *) continue ;;
              esac
              case " $warmed " in
                *" $rom "*) continue ;;
              esac
              warmed="$warmed $rom"
              # -m 8G covers the largest ISO on the share; anything bigger
              # would evict more than it buys on 31 GB of RAM.
              ${pkgs.vmtouch}/bin/vmtouch -t -q -m 8G "$rom" 2>/dev/null &
            done
          done
          sleep 3
        done
      '';
    };
  };
}
