{ ... }:

# Hyper-V guest: integration services (KVP, VSS, time sync, framebuffer).
{
  imports = [ ./guest.nix ];

  virtualisation.hypervGuest.enable = true;
}
