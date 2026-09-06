{ pkgs, inputs, system, hwData, ... }:

let
  protonCachyos = import ./proton.nix { inherit inputs system hwData; };
  # Our own build: Valve bleeding-edge + CachyOS fork patches, from
  # github:aCeTotal/proton-nixlyos via the nixlypkgs overlay.
  protonNixlyos = pkgs.proton-nixlyos;
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
      extraArgs = "-cef-disable-gpu-compositing";
      # Runs on the host before bubblewrap, on every launch: proton-nixlyos
      # everywhere, Library start page, notification popups off. Never fatal.
      extraPreBwrapCmds = "${autoconfig} || true";
    };

    # proton-nixlyos is the default (via autoconfig); Proton-CachyOS stays
    # installed as a manual fallback in the Steam UI.
    extraCompatPackages = [ protonNixlyos protonCachyos ];

    extraPackages = with pkgs; [
      gamemode
      libGL
      libglvnd
    ];
  };

  hardware.steam-hardware.enable = true;
}
