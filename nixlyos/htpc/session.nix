# HTPC session: the machine boots straight into Steam Big Picture.
# SDDM auto-logs in (SDDM.nix gates on nixlyos.mode), nixlytile starts
# htpc-steam from its autostart list (home/nixlytile.nix), and htpc-steam
# keeps Big Picture alive for the whole session.
{ pkgs, lib, config, ... }:

let
  shortcutsCleanup = pkgs.callPackage ./steam-shortcuts.nix { };

  htpcSteam = pkgs.writeShellScriptBin "htpc-steam" ''
    # Keep Big Picture alive: quitting Steam on a couch box just means a
    # black screen, so it is relaunched until the session ends.
    # The old RetroArch/nixlymedia/GeForce NOW shortcuts are removed
    # before every launch (Steam only reads shortcuts.vdf at startup):
    # the apps live on their own nixlytile workspaces now, and a Big
    # Picture shortcut would just start a second instance. Output goes
    # to the journal (journalctl -t htpc-steam-shortcuts). Best-effort:
    # never block Big Picture.
    while :; do
      ${shortcutsCleanup}/bin/htpc-steam-shortcuts-cleanup 2>&1 \
        | ${pkgs.systemd}/bin/systemd-cat -t htpc-steam-shortcuts || true
      steam -tenfoot
      sleep 2
    done
  '';
in
lib.mkIf (config.nixlyos.mode == "htpc") {
  environment.systemPackages = [ htpcSteam shortcutsCleanup ];
}
