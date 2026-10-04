# Discord gets its own push-to-mute gate (bit 1); meeting apps skip push-to-talk.
{ pkgs, ... }:

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
                # Reopen outlasts the talk fade plus one quantum.
                type = "ladspa"; name = "gate";
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

    -- Strict routes never fall back to the default mic.
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
}
