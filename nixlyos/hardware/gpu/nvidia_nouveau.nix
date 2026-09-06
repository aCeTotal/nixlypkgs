{ config, lib, pkgs, hwData, ... }:

# Fermi and older, where nixpkgs marks the proprietary legacy_390/legacy_340
# branches broken, so the in-tree nouveau driver is used instead.
# To try proprietary anyway, pin the branch in scripts/laptop-register.

let
  gpu = hwData.detected;
in
{
  services.xserver.videoDrivers = [ "modesetting" ];

  hardware.graphics = {
    enable = true;
    enable32Bit = true;
    extraPackages = with pkgs; [
      libvdpau-va-gl
    ];
    extraPackages32 = with pkgs.pkgsi686Linux; [
      vulkan-loader
      libvdpau-va-gl
    ];
  };

  # Load nouveau in the initrd so KMS is up before stage 2.
  boot.initrd.kernelModules = [ "nouveau" ];

  hardware.enableRedistributableFirmware = true;

  environment.systemPackages = with pkgs; [
    vulkan-tools
    libva-utils
    mesa-demos
  ];

  environment.sessionVariables = {
    NIXOS_OZONE_WL = "1";
    QT_QPA_PLATFORM = "wayland";
    SDL_VIDEODRIVER = "wayland";
    MOZ_ENABLE_WAYLAND = "1";
    ELECTRON_OZONE_PLATFORM_HINT = "auto";
  };

  warnings = [
    "gpu/nvidia_nouveau.nix: kortet (arkitektur: ${gpu.nvidiaArch}) stoettes bare av NVIDIA legacy_390/legacy_340, som er broken i nixpkgs paa moderne kernel. Bruker nouveau — spillytelse er langt under den proprietaere driveren, og reclocking er begrenset."
  ];
}
