{ config, lib, pkgs, ... }:

{
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
    extraPackages = with pkgs; [
      vulkan-loader
      libva-vdpau-driver
      libvdpau-va-gl
    ];
    extraPackages32 = with pkgs.pkgsi686Linux; [
      vulkan-loader
      libva-vdpau-driver
      libvdpau-va-gl
    ];
  };

  # Opens amdgpu's overdrive tables so CoreCtrl/LACT can write fan and power limits.
  boot.kernelParams = [ "amdgpu.ppfeaturemask=0xffffffff" ];

  environment.systemPackages = with pkgs; [
    vulkan-tools
    libva-utils
    amdgpu_top
  ];

  environment.sessionVariables = {
    LIBVA_DRIVER_NAME = "radeonsi";
    VDPAU_DRIVER = "radeonsi";
    # RADV explicitly, so an amdvlk package in the profile cannot hijack the ICD.
    AMD_VULKAN_ICD = "RADV";
    # glthread globally, not just Mesa's per-app list, for CPU-bound OpenGL titles.
    mesa_glthread = "true";
    # 10G shader cache so eviction never causes recompile stutter.
    MESA_SHADER_CACHE_MAX_SIZE = "10G";
    NIXOS_OZONE_WL = "1";
    QT_QPA_PLATFORM = "wayland";
    SDL_VIDEODRIVER = "wayland";
    MOZ_ENABLE_WAYLAND = "1";
  };
}
