{ nixlyUser, ... }:

let
  home = "/home/${nixlyUser}";
in
{
  systemd.tmpfiles.rules = [
    "d /run/nixly-dlgate 0755 root root -"
    "f /run/nixly-dlgate/events 0644 root root -"
    "d /var/lib/nixly-quarantine 0750 root wheel -"
    "d ${home}/Downloads 0755 ${nixlyUser} users -"
    "d ${home}/Desktop 0755 ${nixlyUser} users -"
  ];
}
