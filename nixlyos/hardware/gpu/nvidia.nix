{ config, lib, pkgs, ... }:

{
  services.xserver.videoDrivers = [ "nvidia" ];

  hardware.graphics = {
    enable = true;
    enable32Bit = true;
    extraPackages32 = with pkgs.pkgsi686Linux; [
      vulkan-loader
    ];
  };

  hardware.nvidia = {
    modesetting.enable = true;
    nvidiaPersistenced = true;
    powerManagement.enable = false;
    powerManagement.finegrained = false;
    open = false;
    nvidiaSettings = false;
    # `cachyos` is chaotic-nyx's prebuilt driver matched to the CachyOS kernel;
    # any other kernel falls back to building `latest` locally.
    package =
      config.boot.kernelPackages.nvidiaPackages.cachyos
        or config.boot.kernelPackages.nvidiaPackages.latest;

    # reverseSync lets the dGPU render the whole session, halving the cross-GPU
    # copies that otherwise cap the Intel-wired eDP panel around 100 FPS.
    prime = {
      reverseSync.enable = true;
      intelBusId = "PCI:0:2:0";
      nvidiaBusId = "PCI:1:0:0";
    };
  };

  boot = {
    initrd.kernelModules = [ "nvidia" "nvidia_uvm" "nvidia_modeset" "nvidia_drm" ];
    kernelParams = [
      "nvidia_drm.modeset=1"
      "nvidia_drm.fbdev=1"
      # PAT for GPU mappings, faster CPU-to-GPU uploads.
      "nvidia.NVreg_UsePageAttributeTable=1"
    ];
  };

  environment.systemPackages = with pkgs; [
    vulkan-tools
    libva-utils
    egl-wayland
    nvidia-vaapi-driver
    nvtopPackages.full
  ];

  # System-wide so SDDM sees them; without these the greeter renders black.
  environment.variables = {
    LIBVA_DRIVER_NAME = "nvidia";
    __GLX_VENDOR_LIBRARY_NAME = "nvidia";
    GBM_BACKEND = "nvidia-drm";
  };

  environment.sessionVariables = {
    ELECTRON_OZONE_PLATFORM_HINT = "auto";
    # Never trim the shader cache mid-session; eviction shows up as recompile hitches.
    __GL_VRR_ALLOWED = "1";
    __GL_GSYNC_ALLOWED = "1";
    __GL_THREADED_OPTIMIZATIONS = "1";
    __GL_SHADER_DISK_CACHE = "1";
    __GL_SHADER_DISK_CACHE_SIZE = "10737418240";   # 10 GiB
    __GL_SHADER_DISK_CACHE_SKIP_CLEANUP = "1";
    MESA_SHADER_CACHE_MAX_SIZE = "10G";
  };

  # Same vars on the unit too, in case the PAM env import races.
  systemd.services.display-manager.environment = {
    GBM_BACKEND = "nvidia-drm";
    __GLX_VENDOR_LIBRARY_NAME = "nvidia";
    LIBVA_DRIVER_NAME = "nvidia";
  };

  # No fan control service: nvfancontrol talks NV-CONTROL, which only a real Xorg
  # with the nvidia driver exports. Xwayland does not, so the GPU BIOS curve runs.
}
