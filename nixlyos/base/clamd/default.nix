{ pkgs, lib, ... }:

let
  idle = pkgs.writeShellApplication {
    name = "nixly-clamd-idle";
    runtimeInputs = with pkgs; [
      gawk
      iproute2
      systemd
    ];
    text = builtins.readFile ./idle.sh;
  };
in
{
  # Socket activation starts it.
  systemd.services.clamav-daemon = {
    wantedBy = lib.mkForce [ ];
    # Freshclam has its own timer.
    wants = lib.mkForce [ ];
    serviceConfig = {
      # Stops must keep the socket.
      RuntimeDirectoryPreserve = true;
      # Hung stop gets SIGKILL.
      TimeoutStopSec = 3;
    };
  };

  systemd.services.nixly-clamd-idle = {
    description = "Stop clamd when idle";
    bindsTo = [ "clamav-daemon.service" ];
    after = [ "clamav-daemon.service" ];
    wantedBy = [ "clamav-daemon.service" ];
    serviceConfig = {
      ExecStart = "${idle}/bin/nixly-clamd-idle";
      Restart = "on-failure";
    };
  };
}
