{ ... }:

# VirtualBox guest additions (shared clipboard, resolution, vboxsf).
{
  imports = [ ./guest.nix ];

  virtualisation.virtualbox.guest.enable = true;
}
