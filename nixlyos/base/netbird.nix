{ lib, ... }:

{
  # Login is browser SSO: run `netbird up` once per machine.
  services.netbird.enable = true;
  # Started by hand, never at boot.
  systemd.services.netbird.wantedBy = lib.mkForce [ ];
  networking.firewall.trustedInterfaces = [ "wt0" ];
}
