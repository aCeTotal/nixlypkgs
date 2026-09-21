{ pkgs, ... }:

let
  approve = pkgs.writeShellApplication {
    name = "nixly-usb-approve";
    runtimeInputs = [ pkgs.usbguard ];
    text = ''
      if [ $# -eq 0 ]; then
        usbguard list-devices --blocked
        echo
        echo "nixly-usb-approve <id>        allow once"
        echo "nixly-usb-approve <id> keep   allow and remember"
        exit 0
      fi
      if [ "''${2:-}" = "keep" ]; then
        usbguard allow-device "$1" -p
      else
        usbguard allow-device "$1"
      fi
    '';
  };
in
{
  # A device that claims a keyboard interface can type commands the moment
  # it is plugged in — the BadUSB attack. Only storage, hubs and known
  # controllers are accepted on hot-plug; anything else waits for an
  # explicit approval from an unlocked session.
  services.usbguard = {
    enable = true;
    implicitPolicyTarget = "block";
    # Devices already attached at boot are trusted: blocking them could lock
    # a USB keyboard out of its own machine.
    presentDevicePolicy = "allow";
    insertedDevicePolicy = "apply-policy";
    IPCAllowedGroups = [ "wheel" ];
    rules = ''
      # Hubs.
      allow with-interface equals { 09:00:00 }

      # Storage, and nothing but storage: a stick that also claims a
      # keyboard does not match this rule and stays blocked.
      allow with-interface equals { 08:06:50 }

      # Phone USB tethering: CDC network interfaces only, no HID.
      allow with-interface equals { 02:0d:00 0a:00:01 0a:00:01 }
      allow with-interface equals { 02:06:00 0a:00:00 }
      allow with-interface equals { e0:01:03 0a:00:00 }

      # Built-in radios. A Bluetooth controller re-enumerates after every
      # controller reset (SCO errors do this), and blocking it there kills
      # Bluetooth until someone approves it by hand. Hardwired only, so a
      # plugged-in BadUSB can never match.
      allow with-interface one-of { e0:01:01 } with-connect-type "hardwired"

      # Game controllers.
      allow id 045e:* with-interface one-of { ff:*:* 03:*:* }
      allow id 054c:* with-interface one-of { 03:*:* ff:*:* }
      allow id 057e:* with-interface one-of { 03:*:* ff:*:* }
      allow id 28de:* with-interface one-of { 03:*:* ff:*:* }
      allow id 2dc8:* with-interface one-of { 03:*:* ff:*:* }

      # Everything else — keyboards, mice, network adapters, combo devices —
      # is blocked until approved with nixly-usb-approve.
    '';
  };

  environment.systemPackages = [ approve ];
}
