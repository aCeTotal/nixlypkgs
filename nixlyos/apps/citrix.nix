{ lib, pkgs, nixlyUser, ... }:

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
        # Citrix's UseFullScreen default spans every monitor as one X window.
        ${pkgs.gnused}/bin/sed -i \
          's/^UseFullScreen[[:space:]]*=.*/UseFullScreen=False/' "$INI"

        # Map drive A: to the home directory; wfica expands $HOME itself.
        ${pkgs.gnused}/bin/sed -i \
          's|^DrivePathA[[:space:]]*=.*|DrivePathA=$HOME|' "$INI"

        # Otherwise the local Super key opens the Windows start menu in-session.
        if ${pkgs.gnugrep}/bin/grep -q '^SuperMetaToWinKeys' "$INI"; then
          ${pkgs.gnused}/bin/sed -i \
            's/^SuperMetaToWinKeys[[:space:]]*=.*/SuperMetaToWinKeys=False/' "$INI"
        else
          ${pkgs.gnused}/bin/sed -i \
            '/^\[WFClient\]/a SuperMetaToWinKeys=False' "$INI"
        fi
      fi
    '';
  };

  # An enterprise policy, since Chrome's own "always open" setting is lost on profile reset.
  environment.etc."opt/chrome/policies/managed/citrix-ica.json".text =
    builtins.toJSON { AutoOpenFileTypes = [ "ica" ]; };
}
