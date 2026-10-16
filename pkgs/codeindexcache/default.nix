# Upstream recipe, pinned by flake.lock.
{ callPackage, src }:

callPackage "${src}/nix/package.nix" { }
