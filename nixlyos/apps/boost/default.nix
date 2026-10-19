# Full priority and dGPU for `nix run`.
{ pkgs, ... }:

let
  boost = pkgs.runCommandCC "nixly-boost" { } ''
    mkdir -p $out/bin
    $CC -O2 -Wall -Wextra -Werror \
      -DGAMEMODE_LIB='"${pkgs.gamemode.lib}/lib"' \
      ${./boost.c} -o $out/bin/nixly-boost
  '';
in
{
  environment.systemPackages = [ boost ];
}
