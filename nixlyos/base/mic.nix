# Automatic microphone setup: echo cancelling, hum and noise removal,
# compression and limiting, inserted between the active microphone and every
# app that records. Both stages are WirePlumber smart filters, so they are
# invisible — the real device stays the default source everywhere, and apps
# are linked through the chain instead of to the device. nixly-mic (the
# daemon) owns the capture volume and the chain's gain stages; see
# pkgs/nixly-mic for the control law.
{ pkgs, ... }:

let
  rnnoise = "${pkgs.rnnoise-plugin}/lib/ladspa/librnnoise_ladspa.so";
  swh = "${pkgs.ladspaPlugins}/lib/ladspa";
in
{
  services.pipewire.extraConfig.pipewire."99-nixly-mic" = {
    "context.modules" = [
      {
        # Reference is the monitor of whatever sink is playing, so apps keep
        # using the real sink and nothing has to be routed by hand.
        name = "libpipewire-module-echo-cancel";
        args = {
          "library.name" = "aec/libspa-aec-webrtc";
          "monitor.mode" = true;
          # webrtc's own AGC is the drift we must not have; rnnoise does
          # better noise suppression than webrtc's.
          "aec.args" = "webrtc.gain_control=false webrtc.noise_suppression=false webrtc.high_pass_filter=true webrtc.mobile_mode=false";
          "audio.rate" = 48000;
          "audio.channels" = 1;
          "node.link-group" = "nixly-mic-ec";
          "capture.props" = {
            "node.name" = "nixly-mic-capture";
            "node.description" = "NixlyMic capture";
          };
          "source.props" = {
            "node.name" = "nixly-mic-ec";
            "node.description" = "Echo cancelled microphone";
            "filter.smart" = true;
            "filter.smart.name" = "nixly-mic-ec";
            # Closest to the device, so it cancels echo before anything else
            # touches the signal. Stated from both sides because the sort only
            # reorders on the entry that is already in the list.
            "filter.smart.after" = [ "nixly-mic" ];
            # nixly-mic's level meter taps the signal here, before the gain
            # stages it controls.
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
                type = "builtin"; name = "hpf"; label = "bq_highpass";
                control = { "Freq" = 85.0; "Q" = 0.707; };
              }
              {
                # Mains hum and its first harmonic, narrow enough to leave a
                # low male voice alone.
                type = "builtin"; name = "hum1"; label = "bq_notch";
                control = { "Freq" = 50.0; "Q" = 20.0; };
              }
              {
                type = "builtin"; name = "hum2"; label = "bq_notch";
                control = { "Freq" = 100.0; "Q" = 20.0; };
              }
              # Two stages so the daemon has ±40 dB of digital range to work in.
              { type = "builtin"; name = "g1"; label = "linear"; control = { "Mult" = 1.0; }; }
              { type = "builtin"; name = "g2"; label = "linear"; control = { "Mult" = 1.0; }; }
              {
                type = "ladspa"; name = "nr"; plugin = rnnoise;
                label = "noise_suppressor_mono";
                control = {
                  "VAD Threshold (%)" = 55.0;
                  "VAD Grace Period (ms)" = 200.0;
                  "Retroactive VAD Grace (ms)" = 60.0;
                };
              }
              {
                # Only removes what rnnoise leaves behind between words.
                type = "builtin"; name = "gate"; label = "noisegate";
                control = {
                  "Open Threshold" = 0.012;
                  "Close Threshold" = 0.008;
                  "Attack (s)" = 0.005;
                  "Hold (s)" = 0.25;
                  "Release (s)" = 0.12;
                };
              }
              {
                type = "ladspa"; name = "comp"; plugin = "${swh}/sc4m_1916.so";
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
                type = "ladspa"; name = "lim";
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
              { output = "nr:Output"; input = "gate:In"; }
              { output = "gate:Out"; input = "comp:Input"; }
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
            # Closest to the app, so the echo canceller sees the raw device.
            "filter.smart.before" = [ "nixly-mic-ec" ];
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
}
