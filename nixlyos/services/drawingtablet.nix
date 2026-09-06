{ config, lib, pkgs, ... }:

{
  hardware.opentabletdriver = {
    enable = true;
    daemon.enable = true;
    blacklistedKernelModules = [ "hid-uclogic" "wacom" ];
  };
}
