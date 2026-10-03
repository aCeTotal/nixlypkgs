{ modulesPath, ... }:

{
  imports = [
    "${modulesPath}/profiles/minimal.nix"
    ./options.nix
    ./kernel.nix
    ./boot.nix
    ./recovery.nix
    ./network.nix
    ./ingress
    ./access.nix
    ./users.nix
    ./nix.nix
    ./updates.nix
    ./audit.nix
    ./headless.nix
  ];
}
