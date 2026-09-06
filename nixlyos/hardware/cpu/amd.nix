{ config, lib, pkgs, ... }:

{
  hardware.cpu.amd.updateMicrocode = true;

  boot = {
    kernelModules = [ "kvm-amd" ];
    # mkBefore must wrap the whole list; `set ++ list` is a type error.
    kernelParams = lib.mkBefore ([
      "amd_pstate=active"
    ] ++ (lib.optionals (config.virtualisation.libvirtd.enable or false) [
      "amd_iommu=on" "iommu=pt"
    ]));
  };
  environment.systemPackages = with pkgs; [
    lm_sensors
    cpufrequtils
  ];
  # power-profiles-daemon off: it owns the governor and overrode perf.nix.
  services.power-profiles-daemon.enable = false;
}
