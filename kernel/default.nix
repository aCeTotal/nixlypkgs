# Kernelene har egen verktøykjede.
inputs:
import ./variants.nix {
  pkgs = import inputs.kernel-nixpkgs {
    system = "x86_64-linux";
    config.allowUnfree = true;
  };
  nixpkgs = inputs.kernel-nixpkgs;
  inherit (inputs)
    linux-src
    linux-vanilla
    cachy-config
    cachy-patches
    ;
  drivers = { inherit (inputs) xone xpadneo msi-ec; };
  caCert = inputs.nixlyos-ca;
}
