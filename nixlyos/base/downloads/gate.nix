{ config, lib, nixlyUser, ... }:

let
  home = "/home/${nixlyUser}";

  # Where downloads land.
  watched = [
    "${home}/Downloads"
    "${home}/Desktop"
    "/tmp"
    "/var/tmp"
  ];
in
{
  # fanotify blocks open() until verdict.
  services.clamav.clamonacc.enable = true;

  services.clamav.daemon.settings = {
    OnAccessPrevention = true;
    OnAccessIncludePath = watched;
    # 2G is the engine ceiling; nothing above it can be scanned at all.
    OnAccessMaxFileSize = "2G";
    OnAccessExcludePath = [ "/nix/tmp" ];
    MaxFileSize = lib.mkForce "2G";
    MaxScanSize = lib.mkForce "4G";
    # Hitting a limit is a verdict of its own, never a silent pass.
    AlertExceedsMax = true;
  };

  systemd.services.clamav-clamonacc.serviceConfig = {
    # Quarantine, never delete: the verdict is triaged afterwards.
    ExecStart = lib.mkForce
      "${config.services.clamav.package}/bin/clamonacc -F --fdpass --move=/var/lib/nixly-quarantine --wait --ping 120:1";
    # Dead clamonacc means no gate.
    Restart = "always";
    RestartSec = 2;
  };

  # Builds must escape the gate.
  systemd.services.nix-daemon.environment.TMPDIR = "/nix/tmp";

  systemd.tmpfiles.rules = [
    "d /nix/tmp 1777 root root -"
    "d /run/nixly-dlgate 0755 root root -"
    "f /run/nixly-dlgate/events 0644 root root -"
    "d /var/lib/nixly-quarantine 0750 root wheel -"
    "d ${home}/Downloads 0755 ${nixlyUser} users -"
    "d ${home}/Desktop 0755 ${nixlyUser} users -"
  ];
}
