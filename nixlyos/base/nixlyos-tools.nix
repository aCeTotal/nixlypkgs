# The NixlyOS command set: hardware detection and system update.
# The scripts live in nixlyos/scripts and get their helpers
# (ui.sh, progress.sh, laptop-register) injected as store paths.
{ pkgs, lib, ... }:

let
  scripts = ../scripts;

  detectHw = pkgs.writeShellApplication {
    name = "nixlyos-detect-hw";
    runtimeInputs = [ pkgs.coreutils ];
    # The detection logic reads /sys directly and has no other dependencies.
    text = ''
      export REGISTER=${scripts + "/laptop-register"}
      ${builtins.readFile (scripts + "/detect-hw.sh")}
    '';
  };

  update = pkgs.writeShellApplication {
    name = "nixlyos-update";
    runtimeInputs = [ pkgs.coreutils pkgs.nix pkgs.gnugrep pkgs.gawk pkgs.jq ];
    # sudo comes from the system (wrapper with setuid), not from nixpkgs.
    text = ''
      export PATH=/run/wrappers/bin:$PATH
      ${builtins.readFile (scripts + "/update.sh")}
    '';
  };
in
{
  environment.systemPackages = [ detectHw update ];
}
