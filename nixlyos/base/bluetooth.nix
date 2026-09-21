{ ... }:

# Keep Bluetooth audio devices alive. Two sleep paths cause mid-use dropouts:
#  1. The adapter side: btusb runtime-autosuspends the USB dongle/chip, which
#     stalls the ACL link until resume — the headset gives up and disconnects.
#     (perf.nix's blanket USB autosuspend rule also exempts class e0 for this.)
#  2. The device side: WirePlumber suspends the bluez sink after a few seconds
#     of silence, closing the A2DP stream; the headset idles out and powers
#     down its radio, then reconnect races/fails.
# Fix: never autosuspend the adapter, and keep the A2DP stream open so the
# headset sees continuous audio frames (silence counts) — that IS the
# keep-alive signal.
{
  boot.extraModprobeConfig = ''
    options btusb enable_autosuspend=0
  '';

  # A connected headset is the one the user is wearing: it outranks every
  # built-in output. Its mic already ranks above the built-in one on its own
  # (2010), which is what nixly-mic picks up behind NixlyMic.
  services.pipewire.wireplumber.extraConfig."55-bluez-priority" = {
    "monitor.bluez.rules" = [
      {
        matches = [ { "node.name" = "~bluez_output\\..*"; } ];
        actions = {
          update-props = {
            "priority.session" = 4000;
            "priority.driver" = 4000;
          };
        };
      }
    ];

    # A profile switch removes the A2DP sink; players must follow the new
    # node instead of being paused, or the audio just stops.
    "wireplumber.settings" = {
      "linking.pause-playback" = false;
      "linking.follow-default-target" = true;
      "linking.allow-moving-streams" = true;
      # Off until nixlytile sees LE Audio duplex; it flips this at runtime.
      "bluetooth.autoswitch-to-headset-profile" = false;
    };
  };

  services.pipewire.wireplumber.extraConfig."54-bluez-keepalive" = {
    "monitor.bluez.rules" = [
      {
        matches = [
          { "node.name" = "~bluez_output\\..*"; }
        ];
        actions = {
          update-props = {
            # 0 = never suspend the sink; the graph keeps streaming (silence)
            # over A2DP so the headset never hits its idle-sleep timer.
            "session.suspend-timeout-seconds" = 0;
            "node.pause-on-idle" = false;
          };
        };
      }
    ];
  };
}
