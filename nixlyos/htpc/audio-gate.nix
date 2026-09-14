# Silence gate for the display (HDMI/DP) audio sink. A Samsung/most TV amps
# hiss whenever a valid-but-silent PCM stream is present, so an app that streams
# continuous digital silence (RetroArch with a core loaded, many games) keeps
# the sink RUNNING and the TV audibly hissing even though "nothing is playing".
#
# audio-gate.py makes a PCM null sink the default output and loops its monitor
# to the real display sink; on GRACE seconds of true silence it drops the
# loopback so the display sink goes idle and suspends (see the suspend-timeout
# rule below), which pulls the HDMI/DP audio infoframe and lets the amp mute.
# The first non-silent sample re-adds the loopback. Short gaps never trigger it,
# so active playback resumes instantly; only sustained silence pays the TV's
# relock cost. Encoded/passthrough streams cannot open the PCM null sink and are
# routed straight to the display sink by WirePlumber, untouched.
{ pkgs, lib, config, nixlyUser, ... }:

lib.mkIf (config.nixlyos.mode == "htpc") {

  # Make the idle display sink suspend ~1 s after the gate drops its loopback,
  # instead of the 5 s default, so the hiss tail after audio stops is short.
  # The gate's own null sink sets suspend-timeout=0 on itself and is not matched
  # here (it is not an alsa hdmi output).
  services.pipewire.wireplumber.extraConfig."56-hdmi-suspend-timeout" = {
    "monitor.alsa.rules" = [
      {
        matches = [ { "node.name" = "~alsa_output.*hdmi.*"; } ];
        actions.update-props."session.suspend-timeout-seconds" = 1;
      }
    ];
  };

  home-manager.users.${nixlyUser} = { pkgs, ... }: {
    systemd.user.services.htpc-audio-gate = {
      Unit = {
        Description = "HTPC: suspend display audio on true silence (kills idle TV hiss)";
        After = [ "graphical-session.target" "wireplumber.service" "pipewire-pulse.service" ];
        PartOf = [ "graphical-session.target" ];
      };
      Install.WantedBy = [ "graphical-session.target" ];
      Service = {
        Type = "simple";
        # Restart keeps the gate fail-safe: the loopback starts UP, so a crash
        # mid-playback leaves audio flowing, and the restart recreates cleanly.
        Restart = "always";
        RestartSec = 2;
        TimeoutStopSec = 5;
        Environment = [
          "PACTL=${pkgs.pulseaudio}/bin/pactl"
          "PAREC=${pkgs.pulseaudio}/bin/parec"
          "PWCLI=${pkgs.pipewire}/bin/pw-cli"
          "GATE_GRACE=1.0"    # seconds of silence before muting the TV
          "GATE_THRESH=100"   # s16 peak floor; below this counts as silence
        ];
        ExecStart = "${pkgs.python3}/bin/python3 ${./audio-gate.py}";
      };
    };
  };
}
