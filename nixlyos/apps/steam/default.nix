{ pkgs, lib, config, hwData, ... }:

let
  # Our own build: Valve bleeding-edge + CachyOS fork patches, from
  # github:aCeTotal/proton-nixlyos via the nixlypkgs overlay. The v3
  # build SIGILLs on pre-AVX2 CPUs; those get the generic build.
  protonNixlyos =
    if hwData.resources.cpuLevel >= 3
    then pkgs.proton-nixlyos
    else pkgs.proton-nixlyos-generic;
  gameWrap = pkgs.callPackage ./gamewrap.nix {
    launchParams = import ./launchparams.nix;
  };
  autoconfig = pkgs.callPackage ./autoconfig.nix {
    inherit gameWrap;
    protonTool = protonNixlyos;
  };
in
{
  programs.steam = {
    enable = true;
    remotePlay.openFirewall = false;
    dedicatedServer.openFirewall = false;

    package = pkgs.steam.override {
      # `-cef-disable-gpu-compositing` for the nixlytile/xwayland-satellite
      # black-window fix; the flag is vendor-agnostic (Intel/AMD/Nvidia).
      # NOT on the HTPC: it forces the CEF UI onto software compositing,
      # and at 4K that makes Big Picture unusably slow. If black windows
      # ever show up in Big Picture, fix that regression instead of
      # re-adding the flag here.
      # (Sep 2026: the HTPC black-screen-at-boot turned out to be a
      # nixlytile segfault on `htpc true` at initial config load, NOT
      # this flag — see nixlytile config_loader.c.)
      extraArgs =
        lib.optionalString (config.nixlyos.mode != "htpc")
          "-cef-disable-gpu-compositing";
      # Runs on the host before bubblewrap, on every launch: proton-nixlyos
      # everywhere, Library start page, notification popups off. Never fatal.
      extraPreBwrapCmds = "${autoconfig} || true";
    };

    extraCompatPackages = [ protonNixlyos ];

    extraPackages = with pkgs; [
      gamemode
      libGL
      libglvnd
    ];
  };

  hardware.steam-hardware.enable = true;
}
