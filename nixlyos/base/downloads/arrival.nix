{ pkgs, nixlyUser, ... }:

let
  arrival = pkgs.writeShellApplication {
    name = "nixly-dlarrival";
    runtimeInputs = with pkgs; [
      attr
      coreutils
      inotify-tools
      (callPackage ../scanbox/file.nix { })
    ];
    text = builtins.readFile ./arrival.sh;
  };
in
{
  # Only new files are scanned, never opens.
  systemd.services.nixly-dlarrival = {
    description = "Scan new files in Downloads";
    after = [ "systemd-tmpfiles-setup.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${arrival}/bin/nixly-dlarrival /home/${nixlyUser}/Downloads";
      Restart = "always";
      RestartSec = 3;
    };
  };
}
