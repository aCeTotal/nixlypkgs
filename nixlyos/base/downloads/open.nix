{ pkgs, ... }:

let
  open = pkgs.writeShellApplication {
    name = "nixly-open-held";
    runtimeInputs = with pkgs; [
      coreutils
      file-roller
    ];
    text = builtins.readFile ./open.sh;
  };
in
{
  # The only sanctioned way to touch a held file.
  environment.systemPackages = [ open ];
}
