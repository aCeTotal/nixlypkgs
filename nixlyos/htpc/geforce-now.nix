# GeForce NOW on the couch: controllers must work inside the flatpak
# sandbox without ever touching mouse/keyboard. The stock manifest does not
# guarantee raw input device access, so a permanent override opens
# /dev (evdev/hidraw for pads) and the udev database (SDL enumerates pads
# through it). Hotplugged pads then appear in the stream immediately.
{ pkgs, lib, config, ... }:

lib.mkIf (config.nixlyos.mode == "htpc") {

  systemd.services.geforce-now-controller-access = {
    description = "Flatpak override: controller access for GeForce NOW";
    wantedBy = [ "multi-user.target" ];
    after = [ "geforce-now-install.service" ];
    path = [ pkgs.flatpak ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      flatpak override --device=all --filesystem=/run/udev:ro com.nvidia.geforcenow
    '';
  };
}
