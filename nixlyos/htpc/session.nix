# HTPC session: the machine boots straight into Steam Big Picture.
# SDDM auto-logs in (SDDM.nix gates on nixlyos.mode), nixlytile starts
# htpc-steam from its autostart list (home/nixlytile.nix), and htpc-steam
# keeps Big Picture alive for the whole session.
{ pkgs, lib, config, ... }:

let
  shortcuts = pkgs.callPackage ./steam-shortcuts.nix { };

  htpcSteam = pkgs.writeShellScriptBin "htpc-steam" ''
    # Shortcuts must exist before Steam starts — it only reads
    # shortcuts.vdf at startup. Best-effort: never block Big Picture.
    ${shortcuts}/bin/htpc-steam-shortcuts || true

    # Keep Big Picture alive: quitting Steam on a couch box just means a
    # black screen, so it is relaunched until the session ends.
    while :; do
      steam -tenfoot
      sleep 2
    done
  '';
in
lib.mkIf (config.nixlyos.mode == "htpc") {
  environment.systemPackages = [ htpcSteam shortcuts ];
}
