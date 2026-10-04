# Push-to-talk gate between NixlyMic and every app (bit 0 of the nixly-gate word).
{ pkgs, ... }:

{
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
                type = "ladspa"; name = "gate";
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
}
