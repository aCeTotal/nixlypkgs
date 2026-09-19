{ pkgs }:

pkgs.writeShellApplication {
  name = "nixly-btpair";
  runtimeInputs = with pkgs; [
    bluez
    coreutils
    gnugrep
  ];
  text = builtins.readFile ./pair.sh;
}
