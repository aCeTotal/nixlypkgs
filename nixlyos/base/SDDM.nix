{ config, pkgs, lib, inputs, nixlyUser, ... }:

let
  opts = import ./options.nix;
  isHtpc = opts.systemMode == 2;
  autoLogin = opts.autoLogin or true;
in
{

  services.displayManager.sddm = {
    enable = true;
    wayland.enable = true;
    autoNumlock = true;
    package = pkgs.kdePackages.sddm;
    theme = "sddm-astronaut-theme";
    extraPackages = with pkgs.kdePackages; [
      qtmultimedia
      qtsvg
      qtvirtualkeyboard
    ];
  };

  environment.systemPackages = [ pkgs.sddm-astronaut ];

  # Auto-login when autoLogin = true OR HTPC mode (options.nix)
  services.displayManager.autoLogin = lib.mkIf (autoLogin || isHtpc) {
    enable = true;
    user = nixlyUser;
  };

}
