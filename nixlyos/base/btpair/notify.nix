{ pkgs, ... }:

let
  notify = pkgs.writeShellApplication {
    name = "nixly-btnotify";
    runtimeInputs = with pkgs; [
      coreutils
      libnotify
    ];
    text = builtins.readFile ./notify.sh;
  };
in
{
  # Re-pairing needs the sync button, so the user has to hear about it.
  systemd.user.services.nixly-btnotify = {
    description = "Bluetooth re-pairing notifications";
    partOf = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];
    wantedBy = [ "graphical-session.target" ];

    serviceConfig = {
      ExecStart = "${notify}/bin/nixly-btnotify";
      Restart = "on-failure";
      RestartSec = 3;
    };
  };
}
