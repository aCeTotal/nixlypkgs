# NVIDIA picks a GFN edge from the resolver's location. Quad9 (the global
# resolver, networking.nix) sends no EDNS Client Subnet, so NVIDIA sees the
# resolver instead of this line and can hand out a farther PoP. A dummy link
# carrying a routing domain sends only the NVIDIA zones to an ECS resolver;
# everything else keeps Quad9 + DoT. Cost: those lookups leak a truncated
# client subnet to Google.
{ ... }:

{
  systemd.network.netdevs."10-gfndns" = {
    netdevConfig = {
      Name = "gfndns";
      Kind = "dummy";
    };
  };

  systemd.network.networks."10-gfndns" = {
    matchConfig.Name = "gfndns";
    networkConfig = {
      DNS = [ "8.8.8.8" "8.8.4.4" ];
      DNSOverTLS = false;
      DNSSEC = false;
      LinkLocalAddressing = "no";
      ConfigureWithoutCarrier = true;
    };
    # Leading ~ = routing domain only, never a search suffix.
    domains = [
      "~nvidia.com"
      "~nvidiagrid.net"
      "~geforcenow.com"
    ];
    linkConfig.ActivationPolicy = "always-up";
  };
}
