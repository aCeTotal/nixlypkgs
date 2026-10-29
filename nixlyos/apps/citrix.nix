{ lib, pkgs, nixlyUser, ... }:

let
  icaOpen = pkgs.writeShellApplication {
    name = "nixly-icaopen";
    runtimeInputs = with pkgs; [
      coreutils
      inotify-tools
      systemd
    ];
    text = ''
      mkdir -p "$HOME/Downloads"
      inotifywait -mq -e moved_to -e close_write --format '%w%f' --include '\.ica$' "$HOME/Downloads" |
        while read -r file; do
          systemd-run --user --quiet -- ${pkgs.citrix-workspace-nixly}/bin/wfica "$file"
        done
    '';
  };
in
{
  # mkAfter, or the nixlypkgs overlay replaces the wfica wrapper below with the
  # unwrapped package.
  nixpkgs.overlays = lib.mkAfter [ (import ../pkgs/citrix/overlay.nix) ];

  environment.systemPackages = with pkgs; [
    citrix-workspace-nixly
  ];

  # Without this daemon wfica writes no logs at all.
  systemd.user.services.ctxcwalogd = {
    description = "Citrix Workspace log daemon";
    wantedBy = [ "default.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.citrix-workspace-nixly}/opt/citrix-icaclient/util/ctxcwalogd";
      Restart = "on-failure";
    };
  };

  # .ica files open in wfica.
  xdg.mime = {
    enable = true;
    addedAssociations."application/x-ica" = "wfica.desktop";
    defaultApplications."application/x-ica" = "wfica.desktop";
  };

  # wfclient.ini is owned by Citrix and cannot be symlinked from the store, so
  # only the keys we need are patched.
  home-manager.users.${nixlyUser} = { lib, ... }: {
    # All_Regions.ini is copied once and never updated, so a new client version's
    # lockdown keys are missing and wfica refuses to start; refresh it from the store.
    home.activation.citrixAllRegionsIni = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      SRC="${pkgs.citrix-workspace-nixly}/opt/citrix-icaclient/config/All_Regions.ini"
      DST="$HOME/.ICAClient/All_Regions.ini"
      if [ -f "$DST" ] && ! cmp -s "$SRC" "$DST"; then
        install -m 600 "$SRC" "$DST"
      fi
    '';

    home.activation.citrixWfclientIni = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      INI="$HOME/.ICAClient/wfclient.ini"
      if [ -f "$INI" ]; then
        # Default fullscreen spans every monitor.
        ${pkgs.gnused}/bin/sed -i \
          's/^UseFullScreen[[:space:]]*=.*/UseFullScreen=False/' "$INI"

        # Read-write home drive, local Super.
        for kv in CDMAllowed=True DriveEnabledA=True 'DrivePathA=$HOME' \
            DriveReadAccessA=0 DriveWriteAccessA=0 SuperMetaToWinKeys=False; do
          key=''${kv%%=*}
          if ${pkgs.gnugrep}/bin/grep -q "^$key[[:space:]]*=" "$INI"; then
            ${pkgs.gnused}/bin/sed -i "s|^$key[[:space:]]*=.*|$kv|" "$INI"
          else
            ${pkgs.gnused}/bin/sed -i "/^\[WFClient\]/a $kv" "$INI"
          fi
        done
      fi
    '';
  };

  # Downloaded .ica opens outside jail.
  systemd.user.services.nixly-icaopen = {
    description = "Open downloaded Citrix launch files";
    partOf = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];
    wantedBy = [ "graphical-session.target" ];
    serviceConfig = {
      ExecStart = "${icaOpen}/bin/nixly-icaopen";
      Restart = "on-failure";
      RestartSec = 3;
    };
  };
}
