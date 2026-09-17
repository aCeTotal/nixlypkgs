{ ... }:

{
  imports = [
    ./gate.nix
    ./warm.nix
    ./triage.nix
    ./oversize.nix
    ./noexec.nix
    ./notify.nix
    ./open.nix
  ];
}
