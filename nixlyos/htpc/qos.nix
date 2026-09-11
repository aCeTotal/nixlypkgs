# Egress priority for the four couch apps, same mechanism as
# apps/geforce-now/qos.nix (which already marks GFN's UDP 49003-49006 EF
# and stays active here): DSCP marks put latency-critical flows in cake's
# priority tin (default qdisc, base/networking.nix) and WiFi WMM's high
# queues. Bulk Steam downloads (TCP) are deliberately left unmarked.
{ lib, config, ... }:

lib.mkIf (config.nixlyos.mode == "htpc") {
  networking.nftables.tables.htpc-qos = {
    family = "inet";
    content = ''
      chain postrouting {
        type filter hook postrouting priority mangle; policy accept;

        # Steam game/voice/Remote Play datagrams (input + ACK path).
        udp dport 27000-27100 ip dscp set ef
        udp dport 27000-27100 ip6 dscp set ef

        # RetroArch netplay (default port).
        udp dport 55435 ip dscp set ef
        udp dport 55435 ip6 dscp set ef

        # nixlymedia -> nixlymediaserver: HTTP stream requests/ACKs plus
        # UDP discovery. CS3 = WMM video queue on WiFi.
        tcp dport 8080 ip dscp set cs3
        tcp dport 8080 ip6 dscp set cs3
        udp dport 8081 ip dscp set cs3
        udp dport 8081 ip6 dscp set cs3
      }
    '';
  };
}
