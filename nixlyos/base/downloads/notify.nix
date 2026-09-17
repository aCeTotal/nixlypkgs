{ pkgs, ... }:

let
  notify = pkgs.writeShellApplication {
    name = "nixly-dlnotify";
    runtimeInputs = with pkgs; [
      coreutils
      libnotify
    ];
    text = builtins.readFile ./notify.sh;
  };
in
{
  # A held file needs a reason on screen.
  systemd.user.services.nixly-dlnotify = {
    description = "Download gate notifications";
    partOf = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];
    wantedBy = [ "graphical-session.target" ];
    serviceConfig = {
      ExecStart = "${notify}/bin/nixly-dlnotify";
      Restart = "on-failure";
      RestartSec = 3;
    };
  };
}
