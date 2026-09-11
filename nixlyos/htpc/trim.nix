# HTPC slimming: background consumers that only make sense on a desktop
# are off, so RAM/CPU/IO stay with Steam, RetroArch, GeForce NOW and
# nixlymedia. Session-side trimming (no appd, no clipman watchers, no
# mcontrolcenter, no activity-prewarm) lives in home/nixlytile.nix's HTPC
# autostart list.
{ lib, config, ... }:

lib.mkIf (config.nixlyos.mode == "htpc") {

  # No drawing tablets on a TV box; the OTD daemon is resident.
  hardware.opentabletdriver.enable = lib.mkForce false;
  hardware.opentabletdriver.daemon.enable = lib.mkForce false;

  # Thumbnailer daemon serves file managers; nothing on the couch uses it.
  services.tumbler.enable = lib.mkForce false;

  # A TV box must never sleep mid-stream (and BT pads cannot wake it).
  systemd.targets.sleep.enable = false;
  systemd.targets.suspend.enable = false;
  systemd.targets.hibernate.enable = false;
  systemd.targets.hybrid-sleep.enable = false;
}
