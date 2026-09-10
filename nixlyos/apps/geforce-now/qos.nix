{ ... }:

{
  # GeForce NOW streams over UDP 49003-49006. Mark egress packets EF so
  # cake (default qdisc, base/networking.nix) puts them in its voice tin
  # ahead of bulk traffic, and WiFi WMM maps them to a priority queue.
  # Egress carries the latency-critical input/ACK path; downstream
  # priority is the router's job and cannot be forced from the host.
  networking.nftables.tables.geforce-now-qos = {
    family = "inet";
    content = ''
      chain postrouting {
        type filter hook postrouting priority mangle; policy accept;
        udp dport 49003-49006 ip dscp set ef
        udp dport 49003-49006 ip6 dscp set ef
      }
    '';
  };
}
