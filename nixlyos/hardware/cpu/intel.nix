{ config, lib, pkgs, ... }:

{
  hardware.cpu.intel.updateMicrocode = true;

  boot = {
    kernelModules = [ "kvm-intel" ];
    # Wrap the entire list with mkBefore; the option expects a list.
    # VT-d always on, never iommu=pt: passthrough mode would leave host
    # devices doing untranslated DMA, which is the attack it exists to stop.
    kernelParams = lib.mkBefore [
      "intel_pstate=active"
      "intel_iommu=on"
    ];
  };

  services.thermald.enable = true;
  # power-profiles-daemon off: it owns the governor and overrode perf.nix.
  services.power-profiles-daemon.enable = false;
  environment.systemPackages = with pkgs; [
    lm_sensors
    cpufrequtils
  ];
}
