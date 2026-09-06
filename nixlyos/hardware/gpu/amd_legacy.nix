{ config, lib, pkgs, ... }:

# Old AMD cards: pre-GCN, GCN1 and GCN2, selected by detect-hw.sh from the PCI ID.
# The kernel params force SI/CIK onto amdgpu, since the default `radeon` has no
# Vulkan and no modern VA-API; pre-GCN cards do not match and stay on radeon.

{
  services.xserver.videoDrivers = [ "modesetting" ];

  hardware.graphics = {
    enable = true;
    enable32Bit = true;
    extraPackages = with pkgs; [
      libva-vdpau-driver
      libvdpau-va-gl
    ];
    extraPackages32 = with pkgs.pkgsi686Linux; [
      vulkan-loader
      libva-vdpau-driver
      libvdpau-va-gl
    ];
  };

  boot.kernelParams = [
    "radeon.si_support=0"
    "amdgpu.si_support=1"
    "radeon.cik_support=0"
    "amdgpu.cik_support=1"
  ];

  hardware.enableRedistributableFirmware = true;

  environment.systemPackages = with pkgs; [
    vulkan-tools
    libva-utils
  ];

  # No LIBVA_DRIVER_NAME: libva picks radeonsi or r600 itself, and hardcoding
  # radeonsi would break VA-API on pre-GCN cards.
  environment.sessionVariables = {
    # glthread helps most on old cards, where the draw-call loop is the bottleneck.
    mesa_glthread = "true";
    NIXOS_OZONE_WL = "1";
    QT_QPA_PLATFORM = "wayland";
    SDL_VIDEODRIVER = "wayland";
    MOZ_ENABLE_WAYLAND = "1";
    ELECTRON_OZONE_PLATFORM_HINT = "auto";
  };

  warnings = [
    "gpu/amd_legacy.nix: gammelt AMD-kort (PCI-ID i pre-GCN/GCN1/GCN2-omraadet). RADV/Vulkan krever GCN1 eller nyere — er kortet TeraScale eller eldre, kjoerer det OpenGL-only, og spill via Proton fungerer ikke."
  ];
}
