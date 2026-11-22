# NixlyOS commands: hardware, update.
{ pkgs, lib, ... }:

let
  scripts = ../scripts;

  detectHw = pkgs.writeShellApplication {
    name = "nixlyos-detect-hw";
    runtimeInputs = [ pkgs.coreutils ];
    # Reads /sys only.
    text = ''
      export REGISTER=${scripts + "/laptop-register"}
      ${builtins.readFile (scripts + "/detect-hw.sh")}
    '';
  };

  userConfig = pkgs.writeShellApplication {
    name = "nixlyos-user-config";
    runtimeInputs = [ pkgs.coreutils pkgs.nix pkgs.gnugrep pkgs.gawk pkgs.jq ];
    text = ''
      export DEFAULT_BINDINGS=${scripts + "/bindings-default.conf"}
      ${builtins.readFile (scripts + "/user-config.sh")}
    '';
  };

  panel = import ../lib/panel-cli.nix { inherit pkgs; };

  update = pkgs.writeShellApplication {
    name = "nixlyos-update";
    runtimeInputs = [ pkgs.coreutils pkgs.nix pkgs.gnugrep pkgs.gnused pkgs.gawk pkgs.jq pkgs.git panel ];
    # Setuid sudo from the system.
    text = ''
      export PATH=/run/wrappers/bin:$PATH
      PROGRESS_AWK=${scripts + "/update-progress.awk"}
      EVAL_NIX=${pkgs.determinate-nix}/bin/nix
      EVAL_APPLY=${scripts + "/update-eval.nix"}
      ${builtins.readFile (scripts + "/update-ui.sh")}
      ${builtins.readFile (scripts + "/update-progress.sh")}
      ${builtins.readFile (scripts + "/update-changes.sh")}
      ${builtins.readFile (scripts + "/update-panel.sh")}
      ${builtins.readFile (scripts + "/update.sh")}
    '';
  };
in
{
  environment.systemPackages = [ detectHw userConfig update ];
}
