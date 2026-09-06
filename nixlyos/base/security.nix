{ config, lib, pkgs, ... }:

{
  networking.firewall.enable = true;
  # nftables loads rules in one transaction, faster at boot than iptables-restore.
  networking.nftables.enable = true;


  security.apparmor.enable = false;

  # Audit off: with no rules configured it was pure logging overhead.
  security.auditd.enable = false;

  programs.firejail.enable = true;

  # Blocks unknown USB devices.
  services.usbguard = {
    enable = false;
    presentDevicePolicy = "allow";   # Allow devices present at boot
    insertedDevicePolicy = "apply-policy";
    # `id` takes VENDOR:PRODUCT; the old three-field form failed to parse.
    rules = ''
      # Standard HID devices.
      allow with-interface 03:*:*

      # Mass storage; drop this line for stricter security.
      allow with-interface 08:*:*

      # USB hubs.
      allow with-interface 09:*:*

      # Xbox controllers.
      allow id 045e:* with-interface one-of { ff:*:* 03:*:* }

      # Generic gamepads and joysticks.
      allow with-interface 03:00:05

      # Sony
      allow id 054c:* with-interface one-of { 03:*:* ff:*:* }
      # Nintendo
      allow id 057e:* with-interface one-of { 03:*:* ff:*:* }
      # Valve
      allow id 28de:* with-interface one-of { 03:*:* ff:*:* }
      # 8BitDo
      allow id 2dc8:* with-interface one-of { 03:*:* ff:*:* }

      # Everything else is blocked by default.
    '';
  };

  # No nixos-upgrade.service: it always failed on the user-owned repo; use the
  # update and upgrade aliases instead.
}
