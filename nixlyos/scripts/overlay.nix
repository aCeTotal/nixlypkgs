# NixlyOS commands.
final: _:

let
  inherit (final) writeShellApplication;
in
{
  nixlyos-panel = writeShellApplication {
    name = "nixlyos-panel";
    runtimeInputs = with final; [ coreutils curl jq gnused gnugrep gawk nix ];
    text = ''
      export NIXLY_PANEL=''${NIXLY_PANEL:-${(import ../lib/panel.nix).url}}
      ${builtins.readFile ./panel.sh}
    '';
  };

  # Reads /sys only.
  nixlyos-detect-hw = writeShellApplication {
    name = "nixlyos-detect-hw";
    runtimeInputs = [ final.coreutils ];
    text = ''
      export REGISTER=${./laptop-register}
      ${builtins.readFile ./detect-hw.sh}
    '';
  };

  nixlyos-user-config = writeShellApplication {
    name = "nixlyos-user-config";
    runtimeInputs = with final; [ coreutils nix gnugrep gawk jq ];
    text = ''
      export DEFAULT_BINDINGS=${./bindings-default.conf}
      ${builtins.readFile ./user-config.sh}
    '';
  };

  # Setuid sudo from the system.
  nixlyos-update = writeShellApplication {
    name = "nixlyos-update";
    runtimeInputs = with final; [ coreutils nix gnugrep gnused gawk jq git nixlyos-panel ];
    text = ''
      export PATH=/run/wrappers/bin:$PATH
      PROGRESS_AWK=${./update-progress.awk}
      EVAL_NIX=${final.determinate-nix}/bin/nix
      EVAL_APPLY=${./update-eval.nix}
      ${builtins.readFile ./update-ui.sh}
      ${builtins.readFile ./update-progress.sh}
      ${builtins.readFile ./update-changes.sh}
      ${builtins.readFile ./update-panel.sh}
      ${builtins.readFile ./update.sh}
    '';
  };

  nixlyos-stage = writeShellApplication {
    name = "nixlyos-stage";
    runtimeInputs = with final; [ coreutils nix gawk nixlyos-panel ];
    text = builtins.readFile ./stage.sh;
  };

  nixly-project-roots = writeShellApplication {
    name = "nixly-project-roots";
    runtimeInputs = with final; [ coreutils nix jq ];
    text = builtins.readFile ./project-roots.sh;
  };
}
