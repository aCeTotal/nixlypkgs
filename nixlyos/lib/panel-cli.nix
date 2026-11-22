# The nixlyos-panel command.
{ pkgs }:

pkgs.writeShellApplication {
  name = "nixlyos-panel";
  runtimeInputs = with pkgs; [ coreutils curl jq gnused gnugrep gawk nix ];
  text = ''
    export NIXLY_PANEL=''${NIXLY_PANEL:-${(import ./panel.nix).url}}
    ${builtins.readFile ../scripts/panel.sh}
  '';
}
