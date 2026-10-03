# Hangs and crashes self-recover.
{ ... }:

{
  systemd.settings.Manager = {
    RuntimeWatchdogSec = "30s";
    RebootWatchdogSec = "5min";
  };

  boot.kernel.sysctl."kernel.panic" = 10;

  # Emergency mode means unreachable.
  systemd.enableEmergencyMode = false;
  boot.initrd.systemd.emergencyAccess = false;

  systemd.coredump.enable = false;
}
