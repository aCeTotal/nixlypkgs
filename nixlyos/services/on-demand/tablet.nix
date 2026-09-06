{ config, lib, pkgs, ... }:

let
  vendorIds = [
    "056a"  # Wacom
    "256c"  # Huion / Gaomon
    "28bd"  # XP-Pen / UGEE / XenceLabs
    "2feb"  # Veikk
    "172f"  # Waltop
  ];

  mkRule = vid: ''
    SUBSYSTEM=="usb", ATTR{idVendor}=="${vid}", TAG+="systemd", ENV{SYSTEMD_USER_WANTS}+="opentabletdriver.service"
    SUBSYSTEM=="hidraw", ATTRS{idVendor}=="${vid}", TAG+="systemd", ENV{SYSTEMD_USER_WANTS}+="opentabletdriver.service"
  '';
in
{
  systemd.user.services.opentabletdriver.wantedBy = lib.mkForce [ ];

  services.udev.extraRules = lib.concatStringsSep "\n" (map mkRule vendorIds);
}
