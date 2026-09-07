# Builds the totalvim neovim package (mnw wrap). Shared by mk-system and
# the flake's packages output so the cached derivation matches what
# machines evaluate.
{ pkgs, system, inputs }:

let
  src = inputs.totalvim;
  plugin = pkgs.callPackage (src + "/plugins/totalvim") { };
in
inputs.mnw.lib.wrap {
  inherit pkgs;
  inputs = {
    self.legacyPackages.${system}.vimPlugins.totalvim = plugin;
  };
} (src + "/nix/mnw")
