# Disk layout every reference machine shares.
{ modulesPath, ... }:

{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  boot.initrd.availableKernelModules = [ "xhci_pci" "ahci" "nvme" "usbhid" "usb_storage" "sd_mod" ];

  fileSystems."/" = {
    device = "/dev/disk/by-partlabel/NIXROOT";
    fsType = "btrfs";
    options = [ "subvol=@root" "noatime" "compress=zstd" ];
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-partlabel/NIXBOOT";
    fsType = "vfat";
    options = [ "fmask=0077" "dmask=0077" ];
  };
}
