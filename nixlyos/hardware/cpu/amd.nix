{ config, lib, pkgs, ... }:

{
  hardware.cpu.amd.updateMicrocode = true;

  boot = {
    kernelModules = [ "kvm-amd" ];
    # mkBefore must wrap the whole list; `set ++ list` is a type error.
    # AMD-Vi always on, never iommu=pt: passthrough mode would leave host
    # devices doing untranslated DMA, which is the attack it exists to stop.
    kernelParams = lib.mkBefore [
      "amd_pstate=active"
      "amd_iommu=on"
    ];
  };
  environment.systemPackages = with pkgs; [
    lm_sensors
    cpufrequtils
  ];
  # power-profiles-daemon off: it owns the governor and overrode perf.nix.
  services.power-profiles-daemon.enable = false;
}
