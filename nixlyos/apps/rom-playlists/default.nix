# Polls the NFS share; no inotify.
{ pkgs, lib, config, nixlyUser, ... }:

let
  retroarch = lib.findFirst (p: (p.meta.mainProgram or null) == "retroarch") null
    config.environment.systemPackages;
  romPlaylists = pkgs.callPackage ./generator.nix { inherit retroarch; };
in
{
  home-manager.users.${nixlyUser} = { ... }: lib.mkIf (retroarch != null) {
    home.packages = [ romPlaylists ];

    systemd.user.services.rom-playlists = {
      Unit.Description = "Generate RetroArch playlists from NFS ROMs";
      Service = {
        Type = "oneshot";
        ExecStart = "${romPlaylists}/bin/rom-playlists";
      };
    };

    systemd.user.timers.rom-playlists = {
      Unit.Description = "Periodic RetroArch playlist re-scan";
      Install.WantedBy = [ "timers.target" ];
      Timer = {
        # Waits for session and network.
        OnStartupSec = "45s";
        OnUnitActiveSec = "30min";
      };
    };
  };
}
