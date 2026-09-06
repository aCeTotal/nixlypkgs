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
    };
  };
}
