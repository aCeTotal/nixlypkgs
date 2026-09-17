{ nixlyUser, ... }:

let
  home = "/home/${nixlyUser}";

  # Self-bind adds the mount flags.
  seal = dir: {
    what = dir;
    where = dir;
    type = "none";
    options = "bind,noexec,nosuid,nodev";
    after = [ "systemd-tmpfiles-setup.service" ];
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
