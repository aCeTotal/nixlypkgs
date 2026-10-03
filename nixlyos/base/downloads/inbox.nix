{ pkgs, nixlyUser, ... }:

let
  home = "/home/${nixlyUser}";
  inbox = "${home}/${import ./inbox-dir.nix}";
  # Root-only, on home's filesystem.
  stage = "/home/.nixly-dlscan";

  expand = pkgs.callPackage ../scanbox/expand.nix { };

  mover = pkgs.writeShellApplication {
    name = "nixly-dlinbox";
    runtimeInputs = with pkgs; [
      clamav
      coreutils
      expand
      inotify-tools
      systemd
    ];
    text = builtins.readFile ./inbox.sh;
  };
in
{
  # Save dialog cannot grant writes.
  environment.etc."brave/policies/managed/downloads.json".text = builtins.toJSON {
    DownloadDirectory = inbox;
    PromptForDownloadLocation = false;
  };

  # Explicit parents stay user-owned.
  systemd.tmpfiles.rules = [
    "d ${home}/.local - ${nixlyUser} users -"
    "d ${home}/.local/share - ${nixlyUser} users -"
    "d ${inbox} 0700 ${nixlyUser} users -"
    "d ${stage} 0700 root root -"
  ];

  systemd.services.nixly-dlinbox = {
    description = "Scan Brave downloads into Downloads";
    after = [ "systemd-tmpfiles-setup.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${mover}/bin/nixly-dlinbox ${inbox} ${home}/Downloads ${stage}";
      Restart = "always";
      RestartSec = 3;
    };
  };
}
