{ nixlyUser, ... }:

let
  home = "/home/${nixlyUser}";

  # Off local-fs.target: tmpfiles cycle.
  seal = dir: {
    what = dir;
    where = dir;
    type = "none";
    options = "bind,noexec,nosuid,nodev";
    unitConfig.DefaultDependencies = false;
    after = [ "systemd-tmpfiles-setup.service" ];
    before = [ "umount.target" ];
    conflicts = [ "umount.target" ];
    wantedBy = [ "multi-user.target" ];
  };
in
{
  # Nothing downloaded is executable in place.
  systemd.mounts = [
    (seal "${home}/Downloads")
    (seal "${home}/Desktop")
    (seal "/var/lib/nixly-quarantine")
  ];
}
