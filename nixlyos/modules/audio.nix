{ pkgs, ... }:

let
  sound = {
    security.rtkit.enable = true;
    services.pulseaudio.enable = false;

    services.pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
      jack.enable = true;
      wireplumber.enable = true;

      wireplumber.extraConfig = {
        # Codecs every HDMI TV knows.
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

        # Empty profiles crashed Steam's libaudio.
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

        # Falls back to "off" profile.
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
            # 2.7 ms for games.
            "default.clock.quantum" = 128;
            # 32 caused RT wakeup storms.
            "default.clock.min-quantum" = 64;
            "default.clock.max-quantum" = 2048;
            "log.level" = 2;
          };
          # Transparent at modest CPU.
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

    # Old WP 0.4 state wins otherwise.
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
      pipewire
      wireplumber
      bluez
      pavucontrol
      pwvucontrol
      crosspipe
      qpwgraph
      alsa-utils
    ];
  };

  # nixly-mic drives the gain stages.
  mic =
    let
      rnnoise = "${pkgs.rnnoise-plugin}/lib/ladspa/librnnoise_ladspa.so";
      swh = "${pkgs.ladspaPlugins}/lib/ladspa";
    in
    {
      services.pipewire.extraConfig.pipewire."99-nixly-mic" = {
        "context.modules" = [
          {
            # Meters before the gain stages.
            name = "libpipewire-module-filter-chain";
            args = {
              "node.description" = "NixlyMic tap";
              "media.name" = "NixlyMic tap";
              "filter.graph" = {
                nodes = [{ type = "builtin"; name = "thru"; label = "copy"; }];
                inputs = [ "thru:In" ];
                outputs = [ "thru:Out" ];
              };
              "node.link-group" = "nixly-mic-tap";
              "capture.props" = {
                "node.name" = "nixly-mic-tap-input";
                "node.description" = "NixlyMic tap input";
                "node.passive" = true;
                "audio.rate" = 48000;
                "audio.channels" = 1;
                "audio.position" = [ "MONO" ];
                "node.latency" = "480/48000";
              };
              "playback.props" = {
                "node.name" = "nixly-mic-tap";
                "node.description" = "NixlyMic tap";
                "media.class" = "Audio/Source";
                "audio.rate" = 48000;
                "audio.channels" = 1;
                "audio.position" = [ "MONO" ];
                "filter.smart" = true;
                "filter.smart.name" = "nixly-mic-tap";
                # Closest to the device.
                "filter.smart.after" = [ "nixly-mic" "nixly-ptt" ];
                "filter.smart.targetable" = true;
              };
            };
          }
          {
            name = "libpipewire-module-filter-chain";
            args = {
              "node.description" = "NixlyMic";
              "media.name" = "NixlyMic";
              "filter.graph" = {
                nodes = [
                  { type = "builtin"; name = "dc"; label = "dcblock"; }
                  {
                    type = "builtin";
                    name = "hpf";
                    label = "bq_highpass";
                    control = { "Freq" = 85.0; "Q" = 0.707; };
                  }
                  {
                    # Mains hum, voice untouched.
                    type = "builtin";
                    name = "hum1";
                    label = "bq_notch";
                    control = { "Freq" = 50.0; "Q" = 20.0; };
                  }
                  {
                    type = "builtin";
                    name = "hum2";
                    label = "bq_notch";
                    control = { "Freq" = 100.0; "Q" = 20.0; };
                  }
                  # ±40 dB digital range.
                  { type = "builtin"; name = "g1"; label = "linear"; control = { "Mult" = 1.0; }; }
                  { type = "builtin"; name = "g2"; label = "linear"; control = { "Mult" = 1.0; }; }
                  {
                    # Suppresses noise, never gates.
                    type = "ladspa";
                    name = "nr";
                    plugin = rnnoise;
                    label = "noise_suppressor_mono";
                    control = {
                      "VAD Threshold (%)" = 0.0;
                      "VAD Grace Period (ms)" = 200.0;
                      "Retroactive VAD Grace (ms)" = 60.0;
                    };
                  }
                  {
                    type = "ladspa";
                    name = "comp";
                    plugin = "${swh}/sc4m_1916.so";
                    label = "sc4m";
                    control = {
                      "RMS/peak" = 0.0;
                      "Attack time (ms)" = 8.0;
                      "Release time (ms)" = 180.0;
                      "Threshold level (dB)" = -26.0;
                      "Ratio (1:n)" = 3.0;
                      "Knee radius (dB)" = 3.0;
                      "Makeup gain (dB)" = 4.0;
                    };
                  }
                  {
                    type = "ladspa";
                    name = "lim";
                    plugin = "${swh}/fast_lookahead_limiter_1913.so";
                    label = "fastLookaheadLimiter";
                    control = {
                      "Input gain (dB)" = 0.0;
                      "Limit (dB)" = -1.5;
                      "Release time (s)" = 0.25;
                    };
                  }
                ];
                links = [
                  { output = "dc:Out 1"; input = "hpf:In"; }
                  { output = "hpf:Out"; input = "hum1:In"; }
                  { output = "hum1:Out"; input = "hum2:In"; }
                  { output = "hum2:Out"; input = "g1:In"; }
                  { output = "g1:Out"; input = "g2:In"; }
                  { output = "g2:Out"; input = "nr:Input"; }
                  { output = "nr:Output"; input = "comp:Input"; }
                  { output = "comp:Output"; input = "lim:Input 1"; }
                ];
                inputs = [ "dc:In 1" ];
                outputs = [ "lim:Output 1" ];
              };
              "node.link-group" = "nixly-mic";
              "capture.props" = {
                "node.name" = "nixly-mic-input";
                "node.description" = "NixlyMic input";
                "node.passive" = true;
                "audio.rate" = 48000;
                "audio.channels" = 1;
                "audio.position" = [ "MONO" ];
                # rnnoise needs 10 ms frames.
                "node.latency" = "480/48000";
              };
              "playback.props" = {
                "node.name" = "nixly-mic";
                "node.description" = "NixlyMic";
                "media.class" = "Audio/Source";
                "audio.rate" = 48000;
                "audio.channels" = 1;
                "audio.position" = [ "MONO" ];
                "filter.smart" = true;
                "filter.smart.name" = "nixly-mic";
                "filter.smart.before" = [ "nixly-mic-tap" ];
                "filter.smart.after" = [ "nixly-ptt" ];
                # Meeting apps skip push-to-talk.
                "filter.smart.targetable" = true;
              };
            };
          }
        ];
      };

      systemd.user.services.nixly-mic = {
        description = "Automatic microphone gain and noise control";
        after = [ "pipewire.service" "wireplumber.service" ];
        wants = [ "wireplumber.service" ];
        partOf = [ "pipewire.service" ];
        wantedBy = [ "pipewire.service" ];
        serviceConfig = {
          Type = "simple";
          ExecStart = "${pkgs.nixly-mic}/bin/nixly-mic";
          Restart = "always";
          RestartSec = 2;
          Slice = "session.slice";
        };
      };

      environment.systemPackages = [ pkgs.nixly-mic ];
    };

  # nixly-gate bit 0.
  pushToTalk = {
    services.pipewire.extraConfig.pipewire."99-nixly-ptt" = {
      "context.modules" = [
        {
          name = "libpipewire-module-filter-chain";
          args = {
            "node.description" = "NixlyMic push-to-talk";
            "media.name" = "NixlyMic push-to-talk";
            "filter.graph" = {
              nodes = [
                {
                  # Faded against release clicks.
                  type = "ladspa";
                  name = "gate";
                  plugin = "${pkgs.nixly-gate}/lib/ladspa/nixly_gate.so";
                  label = "nixly_gate";
                  control = { "Bit" = 0; "Fade (ms)" = 5.0; };
                }
              ];
            };
            "node.link-group" = "nixly-ptt";
            "capture.props" = {
              "node.name" = "nixly-ptt-input";
              "node.description" = "NixlyMic push-to-talk input";
              "node.passive" = true;
              "audio.rate" = 48000;
              "audio.channels" = 1;
              "audio.position" = [ "MONO" ];
              "node.latency" = "480/48000";
            };
            "playback.props" = {
              "node.name" = "nixly-ptt";
              "node.description" = "NixlyMic push-to-talk";
              "media.class" = "Audio/Source";
              "audio.rate" = 48000;
              "audio.channels" = 1;
              "audio.position" = [ "MONO" ];
              "filter.smart" = true;
              "filter.smart.name" = "nixly-ptt";
              # Closest to the app.
              "filter.smart.before" = [ "nixly-mic" ];
            };
          };
        }
      ];
    };
  };

  # Discord push-to-mute, nixly-gate bit 1.
  pushToMute =
    let
      source = "nixly-voip";
    in
    {
      services.pipewire.extraConfig.pipewire."99-nixly-voip" = {
        "context.modules" = [
          {
            name = "libpipewire-module-filter-chain";
            args = {
              "node.description" = "NixlyMic (Discord)";
              "media.name" = "NixlyMic (Discord)";
              "filter.graph" = {
                nodes = [
                  {
                    # Outlasts fade plus one quantum.
                    type = "ladspa";
                    name = "gate";
                    plugin = "${pkgs.nixly-gate}/lib/ladspa/nixly_gate.so";
                    label = "nixly_gate";
                    control = { "Bit" = 1; "Reopen (ms)" = 30.0; };
                  }
                ];
              };
              "node.link-group" = source;
              "capture.props" = {
                "node.name" = "${source}-input";
                "node.description" = "NixlyMic (Discord) input";
                "node.passive" = true;
                "audio.rate" = 48000;
                "audio.channels" = 1;
                "audio.position" = [ "MONO" ];
                "node.latency" = "480/48000";
              };
              "playback.props" = {
                "node.name" = source;
                "node.description" = "NixlyMic (Discord)";
                "media.class" = "Audio/Source";
                "audio.rate" = 48000;
                "audio.channels" = 1;
                "audio.position" = [ "MONO" ];
              };
            };
          }
        ];
      };

      services.pipewire.wireplumber.extraScripts."linking/find-voip-target.lua" = ''
        lutils = require ("linking-utils")
        cutils = require ("common-utils")

        -- Strict routes never use defaults.
        local ROUTES = {
          { target = "${source}", strict = true,
            clients = { "discord", "vesktop", "webcord" } },
          { target = "nixly-mic", strict = false,
            clients = { "teams", "wfica" } },
        }

        local function findRoute (props)
          if props ["media.class"] ~= "Stream/Input/Audio" or
              cutils.parseBool (props ["stream.capture.sink"]) then
            return nil
          end
          local name = string.lower ((props ["application.process.binary"] or "") ..
              " " .. (props ["application.name"] or ""))
          for _, route in ipairs (ROUTES) do
            for _, client in ipairs (route.clients) do
              if string.find (name, client, 1, true) then
                return route
              end
            end
          end
          return nil
        end

        -- Runs first, so moves cannot escape.
        SimpleEventHook {
          name = "linking/find-voip-target",
          before = "linking/find-defined-target",
          interests = {
            EventInterest {
              Constraint { "event.type", "=", "select-target" },
            },
          },
          execute = function (event)
            local _, om, _, props, flags, target =
                lutils:unwrap_select_target_event (event)

            if target then
              return
            end
            local route = findRoute (props)
            if not route then
              return
            end
            local node = om:lookup {
              type = "SiLinkable",
              Constraint { "node.name", "=", route.target },
            }
            if not node and route.strict then
              event:stop_processing ()
            end
            if not node then
              return
            end
            flags.has_defined_target = true
            flags.has_node_defined_target = false
            flags.can_passthrough = false
            event:set_data ("target", node)
          end
        }:register ()
      '';

      services.pipewire.wireplumber.extraConfig."99-nixly-voip" = {
        "wireplumber.components" = [
          {
            name = "linking/find-voip-target.lua";
            type = "script/lua";
            provides = "custom.find-voip-target";
          }
        ];
        "wireplumber.profiles" = {
          main = {
            "custom.find-voip-target" = "required";
          };
        };
      };
    };

  bluetooth =
    let
      pair = pkgs.writeShellApplication {
        name = "nixly-btpair";
        runtimeInputs = with pkgs; [
          bluez
          coreutils
          gnugrep
        ];
        text = ''
          # One-shot bluetoothctl lacks an agent.
          mac=''${1:-}
          if [[ -z $mac ]]; then
            echo "usage: nixly-btpair <mac>" >&2
            exit 1
          fi

          window=''${NIXLY_BTPAIR_WINDOW:-180}

          {
            echo "agent NoInputNoOutput"
            sleep 1
            echo "scan on"

            waited=0
            while (( waited < window )); do
              sleep 3
              waited=$(( waited + 3 ))
              if bluetoothctl info "$mac" | grep -q "Alias:"; then
                break
              fi
            done

            echo "pair $mac"
            sleep 12
            echo "trust $mac"
            sleep 1
            echo "connect $mac"
            sleep 8
            echo "quit"
          } | bluetoothctl >/dev/null 2>&1

          bluetoothctl info "$mac" | grep -q "Connected: yes"
        '';
      };

      watch = pkgs.writeShellApplication {
        name = "nixly-btwatch";
        runtimeInputs = [ pair ]
          ++ (with pkgs; [
          bluez
          coreutils
          gnused
        ]);
        text = ''
          events=/run/nixly-bt/events
          mkdir -p /run/nixly-bt
          chmod 755 /run/nixly-bt
          : >"$events"
          chmod 644 "$events"

          declare -A fails
          hit=0

          stdbuf -oL btmon --no-pager 2>/dev/null | while read -r line; do
            if [[ $line == *"PIN or Key Missing"* ]]; then
              hit=1
              continue
            fi

            if [[ $hit != 1 || $line != *"Address: "* ]]; then
              continue
            fi
            hit=0

            mac=''${line#*Address: }
            mac=''${mac%% *}

            # Dead keys fail every time.
            count=$(( ''${fails[$mac]:-0} + 1 ))
            fails[$mac]=$count
            if (( count < 3 )); then
              continue
            fi
            fails[$mac]=0

            name=$(bluetoothctl info "$mac" | sed -n 's/^[[:space:]]*Name: //p' | head -1)
            bluetoothctl remove "$mac" >/dev/null 2>&1 || true
            printf '%s|%s\n' "$mac" "''${name:-$mac}" >>"$events"
            nixly-btpair "$mac" >/dev/null 2>&1 &
          done
        '';
      };

      notify = pkgs.writeShellApplication {
        name = "nixly-btnotify";
        runtimeInputs = with pkgs; [
          coreutils
          libnotify
        ];
        text = ''
          events=/run/nixly-bt/events

          tail -F -n0 "$events" 2>/dev/null | while IFS='|' read -r _ name; do
            notify-send -u critical -a NixlyOS -t 0 "Controller lost its pairing" \
              "$name
          Hold the sync button until the logo flashes — it re-pairs on its own."
          done
        '';
      };
    in
    {
      hardware.bluetooth = {
        enable = true;
        powerOnBoot = true;
        package = pkgs.bluez-nixly;
        settings = {
          General = {
            Experimental = true;
            KernelExperimental = true;
            ControllerMode = "dual";
            FastConnectable = true;
            # Pads re-bond without removal.
            JustWorksRepairing = "always";
            # Fixed identity address.
            Privacy = "off";
            Class = "0x000100";
          };
          Policy = {
            AutoEnable = true;
            # Link loss only: bursts, then 30 s.
            ReconnectAttempts = 7200;
            ReconnectIntervals = "1,2,4,8,16,30";
            # Pads, audio sinks and handsfree.
            ReconnectUUIDs = "00001124-0000-1000-8000-00805f9b34fb,00001200-0000-1000-8000-00805f9b34fb,0000110b-0000-1000-8000-00805f9b34fb,0000111e-0000-1000-8000-00805f9b34fb";
          };
          LE = {
            MinAdvertisementInterval = 32;
            MaxAdvertisementInterval = 50;
            ScanIntervalAutoConnect = 60;
            # Higher duty jammed 2.4 GHz.
            ScanWindowAutoConnect = 15;
          };
          GATT = {
            Cache = "yes";
            Channels = 3;
            KeySize = 7;
          };
        };
      };

      # Autosuspend dropped headsets mid-use.
      boot.extraModprobeConfig = ''
        options btusb enable_autosuspend=0
      '';

      services.pipewire.wireplumber.extraConfig = {
        # The worn headset wins.
        "55-bluez-priority" = {
          "monitor.bluez.rules" = [
            {
              matches = [{ "node.name" = "~bluez_output\\..*"; }];
              actions = {
                update-props = {
                  "priority.session" = 4000;
                  "priority.driver" = 4000;
                };
              };
            }
          ];

          # Players follow profile switches.
          "wireplumber.settings" = {
            "linking.pause-playback" = false;
            "linking.follow-default-target" = true;
            "linking.allow-moving-streams" = true;
            # nixlytile flips it for LE Audio.
            "bluetooth.autoswitch-to-headset-profile" = false;
          };
        };

        # Silence keeps headsets awake.
        "54-bluez-keepalive" = {
          "monitor.bluez.rules" = [
            {
              matches = [
                { "node.name" = "~bluez_output\\..*"; }
              ];
              actions = {
                update-props = {
                  "session.suspend-timeout-seconds" = 0;
                  "node.pause-on-idle" = false;
                };
              };
            }
          ];
        };
      };

      environment.systemPackages = [ pair ];

      # bluez disables auto-connect after failures.
      systemd.services.nixly-btwatch = {
        description = "Purge Bluetooth bonds the peer no longer holds";
        after = [ "bluetooth.service" ];
        partOf = [ "bluetooth.service" ];
        wantedBy = [ "bluetooth.service" ];

        serviceConfig = {
          Type = "simple";
          ExecStart = "${watch}/bin/nixly-btwatch";
          Restart = "always";
          RestartSec = 5;
        };
      };

      # Re-pairing needs the sync button.
      systemd.user.services.nixly-btnotify = {
        description = "Bluetooth re-pairing notifications";
        partOf = [ "graphical-session.target" ];
        after = [ "graphical-session.target" ];
        wantedBy = [ "graphical-session.target" ];

        serviceConfig = {
          ExecStart = "${notify}/bin/nixly-btnotify";
          Restart = "on-failure";
          RestartSec = 3;
        };
      };
    };
in
{
  imports = [
    sound
    mic
    pushToTalk
    pushToMute
    bluetooth
  ];
}
