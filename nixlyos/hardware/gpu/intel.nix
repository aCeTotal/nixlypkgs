{ config, lib, pkgs, hwData, ... }:

let
  # Every DG2 device ID: Arc A, Arc Pro, embedded and Flex.
  dg2 = [
    "5690" "5691" "5692" "5693" "5694" "5695" "5696" "5697"
    "56a0" "56a1" "56a2" "56a3" "56a4" "56a5" "56a6"
    "56b0" "56b1" "56b2" "56b3" "56ba" "56bb" "56bc" "56bd" "56be" "56bf"
    "56c0" "56c1" "56c2"
  ];
  drives = hwData.detected.primary == "intel";
in
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

  # Early KMS only when Intel drives; Battlemage is xe-only.
  boot.initrd.kernelModules = lib.mkIf drives [ "i915" "xe" ];

  boot.kernelParams = [
    # DG2 on i915: iHD on xe SIGBUSes.
    "i915.force_probe=${lib.concatStringsSep "," dg2}"
    "xe.force_probe=${lib.concatMapStringsSep "," (id: "!${id}") dg2}"

    # Keep KMS state across boot stages so slow TVs are not renegotiated into a fallback mode.
    "i915.fastboot=1"
  ];

  services.xserver.videoDrivers = [ "modesetting" ];

  # GuC/HuC blobs live in linux-firmware; explicit so an Intel-only host is self-contained.
  hardware.enableRedistributableFirmware = true;

  # Keep runtime PM off for the DG2 HDA controller and its HDMI codec only: with
  # PM on, the HDMI sink vanishes after idle. Scoped here instead of the old global
  # snd_hda_intel power_save=0, which also kept the PCH codec (ALC1220) in D0 so
  # the S/PDIF carrier never dropped and the amp hissed on idle.
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="pci", ATTR{class}=="0x040300", ATTR{vendor}=="0x8086", ATTR{device}=="0x4f9?", ATTR{power/control}="on"
    ACTION=="add", SUBSYSTEM=="hdaudio", ATTRS{vendor}=="0x8086", ATTRS{device}=="0x4f9?", ATTR{power/control}="on"
  '';

  environment.systemPackages = with pkgs; [
    vulkan-tools
    libva-utils
    intel-gpu-tools
  ];

  environment.sessionVariables = {
    # Only the session GPU pins VA-API.
    LIBVA_DRIVER_NAME = lib.mkIf drives "iHD";
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
