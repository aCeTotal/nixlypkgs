# BIOS sync: the NFS share holds one shared BIOS folder
# (Emulator/BIOS, layout documented in its README.txt); everything in it
# is copied into RetroArch's system directory on every box, so dropping
# a dump on the share makes it work everywhere. Copy instead of pointing
# system_directory at NFS: cores read BIOS mid-game, and a share hiccup
# must not stall a running emulator. Never deletes local files — cores
# write their own data (dolphin-emu/, memory cards) into system/.
{ pkgs, lib, config, nixlyUser, ... }:

lib.mkIf (config.nixlyos.mode == "htpc") {

  home-manager.users.${nixlyUser} = {
    systemd.user.services.htpc-bios-sync = {
      Unit.Description = "HTPC: sync BIOS files from NFS to RetroArch";
      Service = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "htpc-bios-sync" ''
          set -u
          src=/mnt/nfs/Bigdisk1/Emulator/BIOS
          dst="$HOME/.config/retroarch/system"
          # Share down or folder missing: keep what was synced earlier.
          [ -d "$src" ] || exit 0
          mkdir -p "$dst"
          # _*: the untouched original emulator bundles (_originals/).
          ${pkgs.rsync}/bin/rsync -rt --exclude 'README*' --exclude '_*' \
            "$src/" "$dst/"
        '';
      };
    };

    systemd.user.timers.htpc-bios-sync = {
      Unit.Description = "HTPC: periodic BIOS re-sync";
      Install.WantedBy = [ "timers.target" ];
      Timer = {
        OnStartupSec = "30s";
        OnUnitActiveSec = "30min";
      };
    };
  };
}
