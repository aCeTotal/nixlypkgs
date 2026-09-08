# Kernel-packages for nixlyos-kernelen med nvidiaPackages tatt fra nixpkgs
# unstable: nixos-stable henger etter paa driver-versjoner, unstable foelger
# NVIDIAs nyeste. `latest` blir dermed alltid siste driver etter
# `nix flake update nixpkgs`. Modulene bygges fortsatt mot nixlyos-kernelen
# (linuxPackagesFor faar kernel-drv-en inn), saa maskin og cache evaluerer
# identiske store-paths.
inputs: final: kernel:
let
  unstable = import inputs.nixpkgs {
    inherit (final.stdenv.hostPlatform) system;
    # Samme gating som maskin-instansen (allowUnfree + nvidia.acceptLicense).
    config = import ../nixlyos/lib/pkgs-config.nix;
  };
in
(final.linuxPackagesFor kernel).extend (_: _: {
  inherit (unstable.linuxPackagesFor kernel) nvidiaPackages;
})
