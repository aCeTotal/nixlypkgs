{ config, pkgs, pkgs-stable, inputs, ... }:

{
  programs.appimage = {
    enable = true;
    binfmt = true;
    package = pkgs.squashfuse.override { zstdSupport = true; };
  };
}
