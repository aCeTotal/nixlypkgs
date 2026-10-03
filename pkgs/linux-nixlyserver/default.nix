# LTS kernel, KSPP hardened.
{ lib, linux }:

linux.override {
  structuredExtraConfig = lib.mapAttrs (_: lib.mkForce) (import ./config.nix lib.kernel);
}
