{ config, lib, ... }:

let
  mode = config.nixlyserver.updates;
  machineFlake = "/etc/nixlyserver";
in
lib.mkIf (mode != "manual") {
  system.autoUpgrade = {
    enable = true;
    flake = machineFlake;
    dates = "03:00";
    randomizedDelaySec = "30min";
    persistent = true;
    allowReboot = mode == "auto-reboot";
    rebootWindow = { lower = "03:00"; upper = "05:00"; };
  };

  # Only the tested nixlypkgs pin.
  systemd.services.nixos-upgrade.preStart = ''
    nix flake update nixlypkgs --flake ${machineFlake}
  '';
}
