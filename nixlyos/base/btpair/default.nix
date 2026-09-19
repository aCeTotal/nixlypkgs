{ pkgs, ... }:

{
  imports = [
    ./watch.nix
    ./notify.nix
  ];

  environment.systemPackages = [ (import ./cmd.nix { inherit pkgs; }) ];
}
