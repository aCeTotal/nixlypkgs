{ pkgs, hwData, ... }:

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
      # Pins the 64-bit steamrt3c client.
      extraEnv.STEAM_FORCE_CLIENT = "steamrt64";
      # Runs on the host before bubblewrap, on every launch: proton-nixlyos
      # everywhere, Library start page, notification popups off. Never fatal.
      extraPreBwrapCmds = "${autoconfig} || true";
    };

    extraCompatPackages = [ protonNixlyos ];

    extraPackages = with pkgs; [
      libGL
      libglvnd
    ];
  };

  hardware.steam-hardware.enable = true;
}
