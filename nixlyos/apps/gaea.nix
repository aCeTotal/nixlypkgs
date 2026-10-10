# Gaea terrengverktøy.
{ lib, config, ... }:

lib.mkIf (config.nixlyos.mode == "desktop") {
  home-manager.sharedModules = [
    ({ pkgs, ... }: { home.packages = [ pkgs.gaea ]; })
  ];
}
