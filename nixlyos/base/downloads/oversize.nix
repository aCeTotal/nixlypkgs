{ pkgs, nixlyUser, ... }:

let
  home = "/home/${nixlyUser}";

  expand = pkgs.callPackage ../scanbox/expand.nix { };

  oversize = pkgs.writeShellApplication {
    name = "nixly-dloversize";
    runtimeInputs = with pkgs; [
      coreutils
      expand
      inotify-tools
      systemd
    ];
    text = builtins.readFile ./oversize.sh;
  };
in
{
  # clamd cannot scan past 2G, so those files are quarantined instead.
  systemd.services.nixly-dloversize = {
    description = "Hold downloads too large to scan";
    after = [ "systemd-tmpfiles-setup.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      # Only the download dirs: moving a big file out of /tmp would break
      # whatever program is writing it.
      ExecStart = "${oversize}/bin/nixly-dloversize ${home}/Downloads ${home}/Desktop";
      Restart = "always";
      RestartSec = 3;
    };
  };
}
