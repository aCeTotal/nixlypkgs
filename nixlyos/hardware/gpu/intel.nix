{ config, lib, pkgs, ... }:

{
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
    extraPackages = with pkgs; [
      vulkan-loader
      intel-media-driver       # iHD VA-API driver (HW decode/encode)
      vpl-gpu-rt               # oneVPL runtime (AV1 / VP9 / HEVC on DG2)
      intel-compute-runtime    # OpenCL / Level Zero
      ocl-icd
      libvdpau-va-gl
    ];
    extraPackages32 = with pkgs.pkgsi686Linux; [
      vulkan-loader
      intel-media-driver
      libvdpau-va-gl
    ];
  };

  # Intel Arc DG2: pin to i915, since iHD VA-API on xe SIGBUSes in mmap of GPU BOs.
  boot.initrd.kernelModules = [ "i915" ];

  boot.kernelParams = [
    # Every shipping DG2 device ID, A310 through A770.
    "i915.force_probe=5690,5691,5692,5693,5694,5695,5696,5697,56a0,56a1,56a2,56a3,56a5,56a6"
    "xe.force_probe=!5690,!5691,!5692,!5693,!5694,!5695,!5696,!5697,!56a0,!56a1,!56a2,!56a3,!56a5,!56a6"

    # Runtime PM off on the HDA codec; the HDMI sink otherwise vanishes after idle.
    "snd_hda_intel.power_save=0"

    # Keep KMS state across boot stages so slow TVs are not renegotiated into a fallback mode.
    "i915.fastboot=1"
  ];

  services.xserver.videoDrivers = [ "modesetting" ];

  # GuC/HuC blobs live in linux-firmware; explicit so an Intel-only host is self-contained.
  hardware.enableRedistributableFirmware = true;

  # Same power-save off at module level, which wins on reload.
  boot.extraModprobeConfig = ''
    options snd_hda_intel power_save=0 power_save_controller=N
  '';

  environment.systemPackages = with pkgs; [
    vulkan-tools
    libva-utils
    intel-gpu-tools
  ];

  environment.sessionVariables = {
    LIBVA_DRIVER_NAME = "iHD";
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
