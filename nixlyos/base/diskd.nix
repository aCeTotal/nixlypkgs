{ pkgs, ... }:

{
  # Root helper for the nixlytile Storage popup: partitioning (parted),
  # mkfs and mount go through its socket on /run/nixly-diskd.sock.
  # Mutating commands are refused on the disks holding the system
  # mounts.  Without it the popup shows "Formatting needs nixly-diskd".
  systemd.services.nixly-diskd = {
    description = "nixlytile disk management helper";
    wantedBy = [ "multi-user.target" ];
    path = with pkgs; [
      parted
      util-linux    # wipefs, mount, umount
      e2fsprogs
      btrfs-progs
      xfsprogs
      dosfstools
      exfatprogs
      ntfs3g
      systemd       # udevadm settle
    ];
    serviceConfig = {
      Type = "exec";
      ExecStart = "${pkgs.nixlytile}/bin/nixly-diskd";
      Restart = "on-failure";
      RestartSec = 5;
      # Root with mount and mkfs powers, so fence off everything it does
      # not need. No PrivateMounts: the mounts it makes must be visible
      # to the rest of the system.
      NoNewPrivileges = true;
      ProtectSystem = "full";
      ProtectHome = false;
      ProtectHostname = true;
      ProtectKernelModules = true;
      ProtectKernelLogs = true;
      ProtectControlGroups = true;
      PrivateNetwork = true;
      RestrictAddressFamilies = [ "AF_UNIX" ];
      RestrictNamespaces = true;
      RestrictRealtime = true;
      LockPersonality = true;
      MemoryDenyWriteExecute = true;
      SystemCallArchitectures = "native";
      SystemCallFilter = [ "@system-service" "@mount" "@raw-io" ];
      CapabilityBoundingSet = [
        "CAP_SYS_ADMIN" "CAP_CHOWN" "CAP_FOWNER" "CAP_DAC_OVERRIDE"
        "CAP_MKNOD" "CAP_SYS_RAWIO"
      ];
    };
  };
}
