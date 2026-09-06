{ config, lib, pkgs, ... }:

# Intel iGPU Gen7.5 and older, selected by detect-hw.sh from the PCI ID.
# Unlike gpu/intel_igpu.nix, i965 is the only VA-API driver here, and GuC/HuC
# firmware and intel-compute-runtime are dropped since both start at Gen8.

{
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
    extraPackages = with pkgs; [
      intel-vaapi-driver       # i965: eneste VA-API-driver for Gen7.5 og ned
      libvdpau-va-gl           # VDPAU -> VA-API-shim for eldre spillere
    ];
    extraPackages32 = with pkgs.pkgsi686Linux; [
      vulkan-loader
      intel-vaapi-driver
      libvdpau-va-gl
    ];
  };

  services.xserver.videoDrivers = [ "modesetting" ];

  boot.initrd.kernelModules = [ "i915" ];

  hardware.enableRedistributableFirmware = true;

  environment.systemPackages = with pkgs; [
    vulkan-tools
    libva-utils
    intel-gpu-tools
  ];

  environment.sessionVariables = {
    LIBVA_DRIVER_NAME = "i965";
    mesa_glthread = "true";
    NIXOS_OZONE_WL = "1";
    QT_QPA_PLATFORM = "wayland";
    SDL_VIDEODRIVER = "wayland";
    MOZ_ENABLE_WAYLAND = "1";
    ELECTRON_OZONE_PLATFORM_HINT = "auto";
  };
}
