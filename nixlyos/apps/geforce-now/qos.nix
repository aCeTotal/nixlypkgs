{ ... }:

{
  # GeForce NOW streams over UDP 49000-49200 (NVIDIA's documented range;
  # 49003-49006 is only the classic GameStream subset) and falls back to
  # TCP/443 where UDP is blocked. Mark egress packets EF so cake (base/
  # shape.nix, diffserv4) puts them in its voice tin ahead of bulk traffic,
  # and WiFi WMM maps them to a priority queue. The port rules are the
  # floor; gfn-focus adds a cgroup rule that catches the 443 fallback too.
  # Downstream priority is the router's job and cannot be forced from here.
  networking.nftables.tables.geforce-now-qos = {
    family = "inet";
    content = ''
      chain postrouting {
        type filter hook postrouting priority mangle; policy accept;
        udp dport 49000-49200 ip dscp set ef
        udp dport 49000-49200 ip6 dscp set ef
      }
    '';
  };

  # No inbound port opening: GeForce NOW initiates the UDP flows outbound, so
  # conntrack accepts the replies. Leaving 200 UDP ports open to the LAN and
  # the public IPv6 internet was needless attack surface.
}
