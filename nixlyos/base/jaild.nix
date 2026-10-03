{ pkgs, ... }:

{
  # Portal file picks into firejail.
  systemd.services.nixly-jaild = {
    description = "nixlytile sandbox file grant helper";
    wantedBy = [ "multi-user.target" ];
    path = [ pkgs.polkit ];
    serviceConfig = {
      Type = "exec";
      ExecStart = "${pkgs.nixlytile}/bin/nixly-jaild";
      Restart = "on-failure";
      RestartSec = 5;
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ReadWritePaths = [ "/run" ];
      ProtectHome = "read-only";
      ProtectHostname = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectKernelLogs = true;
      ProtectControlGroups = true;
      PrivateNetwork = true;
      RestrictAddressFamilies = [ "AF_UNIX" ];
      RestrictNamespaces = [ "mnt" ];
      RestrictRealtime = true;
      LockPersonality = true;
      MemoryDenyWriteExecute = true;
      SystemCallArchitectures = "native";
      SystemCallFilter = [ "@system-service" "@mount" "setns" ];
      CapabilityBoundingSet = [
        "CAP_SYS_ADMIN" "CAP_SYS_CHROOT" "CAP_SYS_PTRACE"
        "CAP_DAC_OVERRIDE" "CAP_DAC_READ_SEARCH" "CAP_CHOWN"
        "CAP_SETUID" "CAP_SETGID"
      ];
    };
  };
}
