{ config, lib, hwData, ... }:

let
  hw = hwData.resources;
  nvidia = builtins.elem "nvidia" config.services.xserver.videoDrivers;
  # htpc/trim.nix disables every sleep target.
  laptop = hwData.dmi.isLaptop && config.nixlyos.mode != "htpc";
  # amdgpu dGPUs evict VRAM into RAM; old data lacks amdDgpu.
  vramGiB = if laptop && (hwData.detected.amdDgpu or (hwData.detected.amd != "")) then 16 else 0;
in
# Resume reads the HibernateLocation EFI variable.
lib.mkIf (hwData.platform.bootMode == "efi") {
  # systemd skips zram and records this file's offset in HibernateLocation.
  swapDevices = [{
    device = "/swapfile";
    size = (hw.memGiB + vramGiB + 5) * 1024;
    priority = 0;
  }];

  # Kernel caps it; the 2/5-of-RAM default reclaimed slowly through zram.
  systemd.tmpfiles.rules = [
    "w /sys/power/image_size - - - - ${toString (hw.memGiB * 1024 * 1024 * 1024)}"
  ];

  # Straight to disk: suspend-then-hibernate hung in its S3 resume.
  services.logind.settings.Login = lib.mkIf laptop {
    HandleLidSwitch = "hibernate";
    HandleLidSwitchExternalPower = "hibernate";
  };

  # Preserve VRAM on disk; the driver's default /tmp is tmpfs.
  hardware.nvidia = lib.mkIf (laptop && nvidia
    && lib.versionAtLeast config.hardware.nvidia.package.version "430.09") {
    powerManagement.enable = lib.mkForce true;
    moduleParams.nvidia.NVreg_TemporaryFilePath = "/var/tmp";
  };
}
