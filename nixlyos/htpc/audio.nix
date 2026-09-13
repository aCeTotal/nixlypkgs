# HTPC audio routing: display audio out is always the default sink, profiles
# stay on auto (base/sound.nix) so ACP picks a profile the TV actually
# advertises via EDID. HDMI and DisplayPort share the same ALSA hdmi:x,y
# devices, so the "hdmi" node match covers both connectors; auto-port follows
# whichever one has a display plugged in (ELD/jack detection). The desktop's
# forced hdmi-surround71 profile (home/audio_priority.nix, now desktop-only)
# played as static on the TV.
{ config, lib, pkgs, ... }:

lib.mkIf (config.nixlyos.mode == "htpc") {

  services.pipewire.wireplumber.extraConfig."55-htpc-hdmi-priority" = {
    "monitor.alsa.rules" = [
      {
        matches = [
          { "device.name" = "~alsa_card.*"; }
        ];
        actions = {
          update-props = {
            "api.acp.auto-port" = true;
          };
        };
      }
      {
        matches = [
          { "node.name" = "~alsa_output.*hdmi.*"; }
        ];
        actions = {
          update-props = {
            "priority.session" = 3000;
            "priority.driver" = 3000;
          };
        };
      }
    ];
  };

  # The forced surround71 profile was persisted in WirePlumber state on the
  # box; saved state wins over the auto-profile rule, so strip it once.
  systemd.user.services.htpc-wp-state-reset = {
    description = "Remove stale forced surround71 profile from WirePlumber state";
    before = [ "wireplumber.service" ];
    partOf = [ "wireplumber.service" ];
    wantedBy = [ "wireplumber.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "htpc-wp-state-reset" ''
        set -u
        D="''${XDG_STATE_HOME:-$HOME/.local/state}/wireplumber"
        [ -d "$D" ] || exit 0
        ${pkgs.gnused}/bin/sed -i '/hdmi-surround71/d' \
          "$D/default-profile" "$D/default-routes" 2>/dev/null || true
      '';
    };
  };
}
