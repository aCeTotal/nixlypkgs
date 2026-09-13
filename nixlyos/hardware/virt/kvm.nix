{ ... }:

# QEMU/KVM guest (also bochs and cloud instances). Guest agent for host
# integration, SPICE agent for clipboard/resolution (no-op without SPICE),
# and the virtio stack preloaded so the root disk never hits a device wait
# even when hardware-configuration.nix was generated elsewhere.
{
  imports = [ ./guest.nix ];

  services.qemuGuest.enable = true;
  services.spice-vdagentd.enable = true;

  boot.initrd.availableKernelModules = [
    "virtio_pci"
    "virtio_blk"
    "virtio_scsi"
    "virtio_net"
    "virtio_gpu"
  ];
}
