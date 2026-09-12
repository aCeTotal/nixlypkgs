# HTPC workspace apps: RetroArch (ws 2), GeForce NOW (ws 3) and
# nixlymedia (ws 4) run for the whole session, each fullscreen on its
# own nixlytile workspace (window-rule `workspace N` in
# home/nixlytile.nix). Same supervisor pattern as htpc-steam
# (session.nix): a crash respawns the app immediately, and the
# compositor's workspace rules put it straight back where it belongs.
{ pkgs, lib, config, ... }:

let
  mkAppLoop = name: cmd: pkgs.writeShellScriptBin name ''
    while :; do
      ${cmd} || true
      sleep 1
    done
  '';
in
lib.mkIf (config.nixlyos.mode == "htpc") {
  environment.systemPackages = [
    (mkAppLoop "htpc-retroarch" "retroarch")
    # --password-store=basic: the CEF client otherwise asks the keyring
    # for a master password on a box that autologs in without one.
    (mkAppLoop "htpc-geforcenow"
      "flatpak run com.nvidia.geforcenow --password-store=basic")
    (mkAppLoop "htpc-nixlymedia" "nixlymedia")
  ];
}
