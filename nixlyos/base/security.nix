{ config, lib, pkgs, ... }:

{
  networking.firewall.enable = true;
  # nftables loads rules in one transaction, faster at boot than iptables-restore.
  networking.nftables.enable = true;

  # Connection-flood cap for the window where ssh_gate has port 22 open to the
  # LAN. Sits ahead of the gate's runtime accept rule, so excess new
  # connections are dropped before sshd ever forks.
  networking.firewall.extraInputRules = ''
    tcp dport 22 ct state new limit rate over 10/minute burst 5 packets drop
  '';


  security.apparmor.enable = false;

  # Audit rules live in audit.nix.

  programs.firejail.enable = true;

  # USB device policy and the pre-mount scanner live in usb/.

  # No nixos-upgrade.service: it always failed on the user-owned repo; use the
  # update and upgrade aliases instead.
}
