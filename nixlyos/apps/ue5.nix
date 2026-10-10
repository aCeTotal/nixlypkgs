{ config, lib, pkgs, ... }:

let
  workspace = "/var/cache/ue5";
in
{
  options.nixlyos.ue5.enable = lib.mkEnableOption "Unreal Engine 5 built from the Wayland fork";

  config = lib.mkIf config.nixlyos.ue5.enable {
    environment.systemPackages = [ pkgs.ue5_source ];

    # Incremental UBT tree for nixbld.
    nix.settings.extra-sandbox-paths = [ workspace ];
    systemd.tmpfiles.rules = [ "d ${workspace} 2770 root nixbld -" ];
  };
}
