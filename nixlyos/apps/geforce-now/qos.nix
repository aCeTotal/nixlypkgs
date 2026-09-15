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

  # Conntrack covers replies from the same 5-tuple; an edge that answers
  # from another source port does not get in without this.
  networking.firewall.allowedUDPPortRanges = [
    { from = 49000; to = 49200; }
  ];
}
