# i915 only programs the HDMI/DP audio codec from a full modeset
# (intel_audio_codec_enable runs on the enabling commit, nowhere else).
# On the Arc A770 i915 lights the TV at ~2 s, but snd_hda_intel binds the
# i915 audio component at ~5 s; the compositor then inherits that same mode
# instead of re-doing the modeset, so the codec is never enabled. Every
# eld_valid on the card stays 0, i915_audio_component_get_eld answers
# "Not valid for port A", and the DP transcoder embeds no audio — PipeWire
# shows a healthy HDMI sink and clocks PCM out to a stream nothing decodes.
#
# One forced off/detect cycle on the connected connector is a real modeset
# and enables the codec. It runs before the display manager so the session
# (and the app htpc-app launches) never sees the output disappear; a later
# compositor modeset only re-enables audio, never disables it.
{ pkgs, lib, config, ... }:

lib.mkIf (config.nixlyos.mode == "htpc") {
  systemd.services.htpc-hdmi-audio = {
    description = "Force a modeset so i915 enables the HDMI/DP audio codec";
    wantedBy = [ "multi-user.target" ];
    before = [ "display-manager.service" ];
    after = [ "sound.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "htpc-hdmi-audio" ''
        set -u
        GREP=${pkgs.gnugrep}/bin/grep

        eld_ok() {
          $GREP -lE 'eld_valid[[:space:]]+1' /proc/asound/card*/eld* 2>/dev/null \
            | $GREP -q .
        }

        connected() {
          for s in /sys/class/drm/card*-*/status; do
            [ "$(cat "$s" 2>/dev/null)" = connected ] || continue
            dirname "$s"
            return 0
          done
          return 1
        }

        # Wait for both halves: a connector the TV is on, and the eld files
        # that only exist once snd_hda_intel has bound the audio component.
        # Kicking before the bind would just repeat the boot race.
        have_eld_files() {
          for f in /proc/asound/card*/eld*; do
            [ -e "$f" ] && return 0
          done
          return 1
        }

        for _ in $(seq 30); do
          connected >/dev/null && have_eld_files && break
          sleep 1
        done

        conn=$(connected) || exit 0

        for _ in $(seq 3); do
          eld_ok && exit 0
          echo off    > "$conn/status"
          sleep 2
          echo detect > "$conn/status"
          sleep 3
        done

        eld_ok || echo "htpc-hdmi-audio: ELD still invalid on $conn, TV has no audio" >&2
        exit 0
      '';
    };
  };
}
