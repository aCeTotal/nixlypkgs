# Public ports for enabled services.
{ config, lib, ... }:

let
  code = config.services.codeindexcache;
in
{
  nixlyserver.publicPorts = lib.optionals (code.enable && code.domain != null) [ 80 443 ];
}
