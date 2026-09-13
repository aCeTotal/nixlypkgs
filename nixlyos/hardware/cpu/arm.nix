{ pkgs, ... }:

# ARM SoCs (Raspberry Pi and friends). No microcode packages and no
# kvm-intel/kvm-amd split: KVM is part of the core kernel on ARM, and CPU
# fixes ship as SoC firmware via the board's firmware package.
{
  environment.systemPackages = with pkgs; [
    lm_sensors
  ];
  # power-profiles-daemon off: it owns the governor and overrode perf.nix.
  services.power-profiles-daemon.enable = false;
}
