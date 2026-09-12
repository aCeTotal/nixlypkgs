# RetroArch playlists, kept in sync with the NFS ROM share automatically:
# the generator (rom-playlists.nix) runs shortly after login and then every
# 30 minutes — NFS gives no inotify, so polling is the only way to pick up
# new ROMs. Touching the share triggers the systemd automount; when the
# server is down the old playlists are kept.
{ pkgs, lib, config, nixlyUser, ... }:

let
  romPlaylists = pkgs.callPackage ./rom-playlists.nix { };
in
lib.mkIf (config.nixlyos.mode == "htpc") {

  # Also on PATH for a manual re-scan from a TTY.
  environment.systemPackages = [ romPlaylists ];

  home-manager.users.${nixlyUser} = {
    systemd.user.services.htpc-rom-playlists = {
      Unit.Description = "HTPC: generate RetroArch playlists from NFS ROMs";
      Service = {
        Type = "oneshot";
        ExecStart = "${romPlaylists}/bin/htpc-rom-playlists";
      };
    };

    systemd.user.timers.htpc-rom-playlists = {
      Unit.Description = "HTPC: periodic RetroArch playlist re-scan";
      Install.WantedBy = [ "timers.target" ];
      Timer = {
        # 45s: after the session and network are up, before anyone has
        # navigated to the RetroArch workspace. Metadata-only NFS walk,
        # so it does not fight Steam's cold start for disk bandwidth.
        OnStartupSec = "45s";
        OnUnitActiveSec = "30min";
      };
    };
  };
}
