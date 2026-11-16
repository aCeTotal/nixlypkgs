# Full priority and dGPU for `nix run`.
{ pkgs, ... }:

let
  boost = pkgs.runCommandCC "nixly-boost" { nativeBuildInputs = [ pkgs.makeBinaryWrapper ]; } ''
    mkdir -p $out/libexec
    $CC -O2 -Wall -Wextra -Werror ${./boost.c} -o $out/libexec/nixly-boost
    makeBinaryWrapper ${pkgs.nixly-dgpu}/bin/nixly-dgpu $out/bin/nixly-boost \
      --add-flag $out/libexec/nixly-boost
  '';
in
{
  environment.systemPackages = [ boost ];
}
