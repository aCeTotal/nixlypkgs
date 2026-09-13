# HTPC configuration set. Every module here gates itself on
# nixlyos.mode == "htpc" (set in ~/.local/nixlyos/local.nix), so on a
# desktop this whole directory evaluates to nothing.
{ ... }:

{
  imports = [
    ./session.nix
    ./media.nix
    ./audio.nix
    ./playlists.nix
    ./bios-sync.nix
    ./retroarch-4k.nix
    ./gpu-perf.nix
    ./auto-update.nix
    ./prewarm.nix
    ./controllers.nix
    ./geforce-now.nix
    ./qos.nix
    ./trim.nix
  ];
}
