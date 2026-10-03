{ ... }:

let
  caches = import ../nixlyos/lib/caches.nix;
in
{
  nix = {
    channel.enable = false;
    settings = {
      experimental-features = [ "nix-command" "flakes" ];
      sandbox = true;
      accept-flake-config = false;
      allowed-users = [ "@wheel" ];
      trusted-users = [ "root" ];
      substituters = caches.urls;
      trusted-public-keys = caches.keys;
    };
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };
    optimise.automatic = true;
  };
}
