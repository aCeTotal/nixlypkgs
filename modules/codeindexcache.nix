# Code index and agent memory on code.aceclan.no.
inputs:
{ lib, pkgs, ... }:

{
  imports = [ "${inputs.codeindexcache_src}/nix/module.nix" ];

  services.codeindexcache = {
    package = lib.mkDefault (pkgs.callPackage ../pkgs/codeindexcache { src = inputs.codeindexcache_src; });
    domain = lib.mkDefault "code.aceclan.no";
  };
}
