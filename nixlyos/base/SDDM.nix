{ config, pkgs, lib, inputs, nixlyUser, ... }:

let
  opts = import ./options.nix;
  # HTPC always auto-logs in; nixlyos.mode comes from local.nix (mode.nix).
  isHtpc = config.nixlyos.mode == "htpc";
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

  # HTPC: no greeter ever — also re-login after logout or a crashed session,
  # otherwise SDDM shows the password prompt the second time around.
  services.displayManager.sddm.autoLogin.relogin = isHtpc;

}
