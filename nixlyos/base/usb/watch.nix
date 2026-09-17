{ pkgs, ... }:

let
  watch = pkgs.writeShellApplication {
    name = "nixly-usbwatch";
    runtimeInputs = with pkgs; [
      coreutils
      inotify-tools
      libnotify
      nautilus
      socat
      util-linux
    ];
    text = builtins.readFile ./watch.sh;
  };
in
{
  # The scanner runs as root and has no session bus; this reads its state
  # files and draws the card the user actually sees.
  systemd.user.services.nixly-usbwatch = {
    description = "USB scan notifications and auto-mount";
    partOf = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];
    wantedBy = [ "graphical-session.target" ];
    serviceConfig = {
      ExecStart = "${watch}/bin/nixly-usbwatch";
      Restart = "on-failure";
      RestartSec = 3;
    };
  };
}
