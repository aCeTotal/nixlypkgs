# STM32CubeIDE — full generic Linux release.
# Bundles the Eclipse IDE, the integrated STM32CubeMX device configurator,
# the GNU Arm toolchain, GDB and ST-Link/J-Link support.
#
# Wire the sha256 of your downloaded installer via an override, e.g.:
#   stm32cubeide.override { sha256 = "sha256-...."; }
{ lib
, callPackage
, buildFHSEnv
, writeShellScript

, version ? "2.2.0"
, sha256 ? lib.fakeSha256
}:

let
  stm32cubeide-unwrapped =
    callPackage ./unwrapped.nix { inherit version sha256; };
in
callPackage ./fhs.nix {
  inherit buildFHSEnv writeShellScript stm32cubeide-unwrapped;
}
