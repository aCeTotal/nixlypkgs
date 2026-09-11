# HTPC configuration set. Every module here gates itself on
# nixlyos.mode == "htpc" (set in ~/.local/nixlyos/local.nix), so on a
# desktop this whole directory evaluates to nothing.
{ ... }:

{
  imports = [
    ./session.nix
    ./workspace-apps.nix
    ./media.nix
    ./auto-update.nix
    ./prewarm.nix
    ./controllers.nix
    ./geforce-now.nix
    ./qos.nix
    ./trim.nix
  ];
}
