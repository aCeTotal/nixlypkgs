{ lib, ... }:

{
  services.hardware.openrgb.enable = lib.mkForce false;
  boot.kernelModules = [ "i2c-dev" ];

  # input.nix (nixlycc-generated, so overridden here) makes this a
  # oneshot wanted by multi-user.target: the 8 s openrgb device scan
  # then blocks the whole boot — graphical.target waited at 9.9 s with
  # everything else ready at 3.5 s.  Type=exec starts it and moves on.
  systemd.services.nixly-input-hardware.serviceConfig.Type = lib.mkForce "exec";

  systemd.timers.logrotate.timerConfig.OnCalendar = lib.mkForce "daily";
}
