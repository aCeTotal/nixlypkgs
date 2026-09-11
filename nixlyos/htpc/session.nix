# HTPC session: the machine boots straight into Steam Big Picture.
# SDDM auto-logs in (SDDM.nix gates on nixlyos.mode), nixlytile starts
# htpc-steam from its autostart list (home/nixlytile.nix), and htpc-steam
# keeps Big Picture alive for the whole session.
{ pkgs, lib, config, ... }:

let
  shortcuts = pkgs.callPackage ./steam-shortcuts.nix { };

  htpcSteam = pkgs.writeShellScriptBin "htpc-steam" ''
    # Keep Big Picture alive: quitting Steam on a couch box just means a
    # black screen, so it is relaunched until the session ends.
    # Shortcuts are (re)written before every launch, not just the first:
    # Steam only reads shortcuts.vdf at startup, and on the very first
    # boot userdata/ does not exist until the user has logged in once —
    # the rewrite after Steam exits/restarts covers that case. Output
    # goes to the journal so a missing shortcut is diagnosable
    # (journalctl -t htpc-steam-shortcuts). Best-effort: never block
    # Big Picture.
    while :; do
      ${shortcuts}/bin/htpc-steam-shortcuts 2>&1 \
        | ${pkgs.systemd}/bin/systemd-cat -t htpc-steam-shortcuts || true
      steam -tenfoot
      sleep 2
    done
  '';
in
lib.mkIf (config.nixlyos.mode == "htpc") {
  environment.systemPackages = [ htpcSteam shortcuts ];
}
