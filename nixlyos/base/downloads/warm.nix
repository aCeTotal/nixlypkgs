{ pkgs, nixlyUser, ... }:

let
  home = "/home/${nixlyUser}";

  warm = pkgs.writeShellApplication {
    name = "nixly-dlwarm";
    runtimeInputs = with pkgs; [
      inotify-tools
      systemd
    ];
    text = builtins.readFile ./warm.sh;
  };
in
{
  # Signatures cost ~1 GB, so clamd is loaded on demand.
  systemd.services.nixly-dlwarm = {
    description = "Warm clamd when a download arrives";
    after = [ "systemd-tmpfiles-setup.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${warm}/bin/nixly-dlwarm ${home}/Downloads ${home}/Desktop /tmp /var/tmp";
      Restart = "always";
      RestartSec = 3;
    };
  };
}
