{ pkgs, ... }:

let
  watch = pkgs.writeShellApplication {
    name = "nixly-btwatch";
    runtimeInputs = [ (import ./cmd.nix { inherit pkgs; }) ]
      ++ (with pkgs; [
        bluez
        coreutils
        gnused
      ]);
    text = builtins.readFile ./watch.sh;
  };
in
{
  # A peer that dropped its key makes bluez retry a dead LTK, then disable
  # auto-connect for good (device.c, AUTH_FAILURES_THRESHOLD) while keeping
  # the bond — the pad is then invisible to the kernel accept list forever.
  systemd.services.nixly-btwatch = {
    description = "Purge Bluetooth bonds the peer no longer holds";
    after = [ "bluetooth.service" ];
    partOf = [ "bluetooth.service" ];
    wantedBy = [ "bluetooth.target" ];

    serviceConfig = {
      Type = "simple";
      ExecStart = "${watch}/bin/nixly-btwatch";
      Restart = "always";
      RestartSec = 5;
    };
  };
}
