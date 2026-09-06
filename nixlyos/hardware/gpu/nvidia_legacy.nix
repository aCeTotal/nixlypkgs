{ config, lib, pkgs, hwData, ... }:

# Old NVIDIA cards whose architecture needs a driver branch other than `latest`;
# detect-hw.sh picks the branch and writes it to detected.nix.

let
  gpu = hwData.detected;
  np = config.boot.kernelPackages.nvidiaPackages;

  # Fall back to latest if nixpkgs dropped the branch upstream.
  branch = if builtins.hasAttr gpu.nvidiaBranch np then gpu.nvidiaBranch else "latest";

  # 470 was the last branch with GBM; wlroots and SDDM Wayland need it.
  gbmOk = !(builtins.elem branch [ "legacy_390" "legacy_340" ]);

  hybrid = gpu.intel != "";
in
{
  services.xserver.videoDrivers = [ "nvidia" ];

  hardware.graphics = {
    enable = true;
    enable32Bit = true;
    extraPackages = with pkgs; [
      vulkan-loader
      libGL
      libglvnd
    ];
    extraPackages32 = with pkgs.pkgsi686Linux; [
      vulkan-loader
      libGL
      libglvnd
    ];
  };

  hardware.nvidia = {
    package = np.${branch};

    modesetting.enable = gbmOk;
    # The persistenced/settings binaries are missing from the oldest packages.
    nvidiaPersistenced = gbmOk;
    nvidiaSettings = false;
    powerManagement.enable = false;
    powerManagement.finegrained = false;
    # Always proprietary; the open modules only exist for Turing and newer.
    open = false;

    # Prime only when an iGPU is actually present.
    prime = lib.mkIf (hybrid && gbmOk) {
      offload.enable = true;
      offload.enableOffloadCmd = true;
      intelBusId = gpu.intel;
      nvidiaBusId = gpu.nvidia;
    };
  };

  boot = {
    initrd.kernelModules = [ "nvidia" "nvidia_uvm" "nvidia_modeset" ]
      ++ lib.optional gbmOk "nvidia_drm";

    kernelParams =
      # PAT for GPU mappings; present in every branch here.
      [ "nvidia.NVreg_UsePageAttributeTable=1" ]
      ++ lib.optionals gbmOk [
        "nvidia_drm.modeset=1"
        "nvidia_drm.fbdev=1"
        # ReBAR arrived in 465; unknown params break modprobe in the initrd.
        "nvidia.NVreg_EnableResizableBar=1"
        # Skip zeroing new GPU memory; accepted on a single-user desktop.
        "nvidia.NVreg_InitializeSystemMemoryAllocations=0"
      ];
  };

  # nvidia-vaapi-driver needs 470+, so 390/340 must record via NVENC directly.
  environment.systemPackages = with pkgs; [
    vulkan-tools
    libva-utils
    nvtopPackages.full
  ] ++ lib.optionals gbmOk [
    egl-wayland
    nvidia-vaapi-driver
  ];

  # Same gaming settings as the modern cards; every branch here supports them.
  environment.sessionVariables = {
    __GL_VRR_ALLOWED = "1";
    __GL_GSYNC_ALLOWED = "1";
    __GL_THREADED_OPTIMIZATIONS = "1";
    __GL_SHADER_DISK_CACHE = "1";
    __GL_SHADER_DISK_CACHE_SIZE = "10737418240";
    __GL_SHADER_DISK_CACHE_SKIP_CLEANUP = "1";
    ELECTRON_OZONE_PLATFORM_HINT = "auto";
  };

  # GBM/GLX vendor only when the branch has GBM and no iGPU drives the panel.
  environment.variables = lib.mkIf (gbmOk && !hybrid) {
    LIBVA_DRIVER_NAME = "nvidia";
    __GLX_VENDOR_LIBRARY_NAME = "nvidia";
    GBM_BACKEND = "nvidia-drm";
  };

  systemd.services.display-manager.environment = lib.mkIf (gbmOk && !hybrid) {
    GBM_BACKEND = "nvidia-drm";
    __GLX_VENDOR_LIBRARY_NAME = "nvidia";
    LIBVA_DRIVER_NAME = "nvidia";
  };

  # Blockers this module cannot fix.
  warnings =
    lib.optional (!gbmOk)
      "gpu/nvidia_legacy.nix: ${branch} har ingen GBM-stoette. SDDM Wayland og nixlytile starter ikke paa dette kortet (arkitektur: ${gpu.nvidiaArch})."
    ++ lib.optional (branch != "latest")
      "gpu/nvidia_legacy.nix: ${branch} bygger bare mot eldre kernel-serier. Feiler kernel-modulen, maa boot.kernelPackages pinnes lavere enn zen/cachyos-valget i boot.nix.";
}
