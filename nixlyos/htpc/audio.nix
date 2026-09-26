# HTPC: display audio, always 5.1.
{ config, lib, pkgs, ... }:

let
  # Stereo gets LFE: 2.1.
  upmix = {
    "channelmix.upmix" = true;
    "channelmix.lfe-cutoff" = 120;
  };
in
lib.mkIf (config.nixlyos.mode == "htpc") {

  services.pipewire.extraConfig.client."60-htpc-upmix"."stream.properties" = upmix;
  services.pipewire.extraConfig.pipewire-pulse."60-htpc-upmix"."stream.properties" = upmix;

  services.pipewire.wireplumber.extraConfig."55-htpc-hdmi-priority" = {
    "device.profile.priority.rules" = [
      {
        matches = [
          { "device.name" = "~alsa_card.*"; }
        ];
        actions = {
          update-props = {
            priorities = [ "output:hdmi-surround" "output:hdmi-stereo" ];
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
