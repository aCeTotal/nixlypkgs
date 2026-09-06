{ ... }:

{
  # dcspitd serves web surfaces to tablets and phones, announced as dcspit.local.

  # The web surfaces and the mDNS responder must both be allowed through.
  networking.firewall.allowedTCPPorts = [ 8080 ];
  networking.firewall.allowedUDPPorts = [ 5353 ];

  # systemd-resolved ignores mDNS from the same machine, so dcspit.local resolves
  # from the tablet but not locally; /etc/hosts is read before all scopes.
  networking.hosts."127.0.0.1" = [ "dcspit.local" ];
}
