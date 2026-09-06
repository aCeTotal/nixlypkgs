{ config, lib, pkgs, ... }:

# Intel iGPU, Gen8 through Gen11, with iHD primary and i965 as legacy-codec fallback.
# Orthogonal to gpu/intel.nix; on a hybrid box both import and the package lists merge.

{
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
    extraPackages = with pkgs; [
      intel-media-driver       # iHD: Gen8+ VA-API (primary on KBL)
      intel-vaapi-driver       # i965: legacy codec fallback
      libvdpau-va-gl           # VDPAU → VA-API shim for older players
    ];
    extraPackages32 = with pkgs.pkgsi686Linux; [
      intel-media-driver
      intel-vaapi-driver
      libvdpau-va-gl
    ];
  };

  boot.initrd.kernelModules = [ "i915" ];

  # Keep KMS state across boot stages so the EDID mode survives without a flicker.
  boot.kernelParams = [ "i915.fastboot=1" ];

  # enable_guc=3 loads GuC and HuC for the media engine; FBC is off because it
  # caused an atomic-commit storm on eDP plane 1A during fullscreen video.
  boot.extraModprobeConfig = ''
    options i915 enable_guc=3 enable_fbc=0
  '';

  hardware.enableRedistributableFirmware = true;

  environment.sessionVariables = {
    # glthread globally, not just Mesa's per-app list, for CPU-bound OpenGL titles.
    mesa_glthread = "true";
    # 10G shader cache so eviction never causes recompile stutter.
    MESA_SHADER_CACHE_MAX_SIZE = "10G";
  };
}
