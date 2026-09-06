{ config, lib, pkgs, ... }:

{
  security.rtkit.enable = true;
  services.pulseaudio.enable = false;
  # Bluetooth UI lives in nixlytile (talks straight to bluetoothd);
  # blueman is gone.

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;
    wireplumber.enable = true;

    wireplumber.extraConfig = {
      # Pin the iec958 codec list every HDMI 1.4+ TV understands; WP 0.5 rejects
      # passthrough when the requested codec is missing from the route's list.
      "51-hdmi-iec958-codecs" = {
        "monitor.alsa.rules" = [
          {
            matches = [
              { "alsa.card_name" = "~HDA Intel HDMI"; }
            ];
            actions = {
              update-props = {
                "api.alsa.iec958.codecs" = [ "PCM" "AC3" "EAC3" ];
              };
            };
          }
        ];
      };

      # Split mode leaves cards without available ports with an empty profile list,
      # which makes Steam's 32-bit libaudio.so deref a NULL active_profile.
      "52-no-split-pcm" = {
        "monitor.alsa.rules" = [
          {
            matches = [
              { "device.name" = "~alsa_card.*"; }
            ];
            actions = {
              update-props = {
                "api.alsa.split-enable" = false;
              };
            };
          }
        ];
      };

      # 52 alone did not hold on PipeWire 1.6.6; re-enabling auto-profile makes ACP
      # fall back to "off" so the profile list is never empty.
      "53-acp-auto-profile" = {
        "monitor.alsa.rules" = [
          {
            matches = [
              { "device.name" = "~alsa_card.*"; }
            ];
            actions = {
              update-props = {
                "api.acp.auto-profile" = true;
              };
            };
          }
        ];
      };
    };

    extraConfig = {
      pipewire."92-low-latency" = {
        "context.properties" = {
          "default.clock.rate" = 48000;
          "default.clock.allowed-rates" = [ 48000 44100 96000 192000 ];
          # Default 128 (2.7 ms) for games, but let clients ask for bigger buffers;
          # the graph follows the lowest active request.
          "default.clock.quantum" = 128;
          # 32 let one greedy client drag the whole graph to ~1500 RT
          # wakeups/s at rtprio 95, preempting game and compositor. 64
          # (1.3 ms) is still far below audible voice/PTT latency.
          "default.clock.min-quantum" = 64;
          "default.clock.max-quantum" = 2048;
          "log.level" = 2;
        };
        # Quality 4 is the transparent/CPU balance; 9 cost measurable CPU per stream.
        "stream.properties" = {
          "resample.quality" = 4;
        };
      };
      pipewire-pulse."92-low-latency" = {
        "stream.properties" = {
          "resample.quality" = 4;
        };
      };
    };
  };

  # Rewrite stale WP 0.4 route state, whose persisted iec958Codecs list wins over
  # the card-level rule above.
  systemd.user.services.wireplumber-route-migrate = {
    description = "Rewrite stale WirePlumber 0.4 route state for WP 0.5";
    before = [ "wireplumber.service" ];
    partOf = [ "wireplumber.service" ];
    wantedBy = [ "wireplumber.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "wp-route-migrate" ''
        set -u
        STATE="''${XDG_STATE_HOME:-$HOME/.local/state}/wireplumber/default-routes"
        [ -f "$STATE" ] || exit 0
        ${pkgs.gnused}/bin/sed -i -E \
          's|"iec958Codecs":\[[^]]*\]|"iec958Codecs":["PCM", "AC3", "EAC3"]|g' \
          "$STATE"
      '';
    };
  };

  environment.systemPackages = with pkgs; [
    pipewire           # provides pw-cli, pw-top, pw-dump, pw-link
    wireplumber        # provides wpctl
    bluez              # bluetoothctl for scripting/debugging

    pavucontrol
    pwvucontrol
    crosspipe
    qpwgraph

    alsa-utils
  ];
}
