{ config, lib, pkgs, ... }:

{
  networking.firewall.enable = true;
  # nftables loads rules in one transaction, faster at boot than iptables-restore.
  networking.nftables.enable = true;
  # Don't answer pings from off-box: no free host discovery on the LAN.
  networking.firewall.allowPing = false;

  # No core dumps land on disk; a crash never spills process memory.
  systemd.coredump.enable = false;

  # SSH is reachable only over the trusted tailscale0 interface (ssh.nix sets
  # openFirewall = false); port 22 is never opened to the LAN or internet.

  security.apparmor.enable = false;

  # Audit rules live in audit.nix.

  # Profiles live in sandbox.nix.
  programs.firejail.enable = true;

  # USB device policy and the pre-mount scanner live in usb/.

  # No nixos-upgrade.service: it always failed on the user-owned repo; use the
  # update and upgrade aliases instead.
}
