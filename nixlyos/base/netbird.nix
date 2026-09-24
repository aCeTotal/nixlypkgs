{ ... }:

{
  # Login is browser SSO: run `netbird up` once per machine.
  services.netbird.enable = true;
  networking.firewall.trustedInterfaces = [ "wt0" ];
}
