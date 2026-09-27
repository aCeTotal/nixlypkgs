# HTPC: display audio, stereo; receiver adds sub.
{ config, lib, pkgs, ... }:

lib.mkIf (config.nixlyos.mode == "htpc") {

  services.pipewire.wireplumber.extraConfig."55-htpc-hdmi-priority" = {
    "device.profile.priority.rules" = [
      {
        matches = [
          { "device.name" = "~alsa_card.*"; }
        ];
        actions = {
          update-props = {
            priorities = [ "output:hdmi-stereo" ];
          };
        };
      }
    ];
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

  # Saved surround state beats priorities.
  systemd.user.services.htpc-wp-state-reset = {
    description = "Remove saved surround profiles from WirePlumber state";
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
        ${pkgs.gnused}/bin/sed -i '/hdmi-surround/d' \
          "$D/default-profile" "$D/default-routes" 2>/dev/null || true
      '';
    };
  };
}
