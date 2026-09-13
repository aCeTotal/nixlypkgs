{ ... }:

# VMware guest: open-vm-tools (time sync, clipboard, resolution).
{
  imports = [ ./guest.nix ];

  virtualisation.vmware.guest.enable = true;

  boot.initrd.availableKernelModules = [
    "mptspi"
    "vmw_pvscsi"
  ];
}
