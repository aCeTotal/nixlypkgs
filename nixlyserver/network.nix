{ ... }:

{
  networking.useNetworkd = true;
  networking.useDHCP = true;

  networking.nftables.enable = true;
  networking.firewall = {
    enable = true;
    allowPing = false;
  };

  # Quad9 over TLS only.
  networking.nameservers = [
    "9.9.9.9#dns.quad9.net"
    "149.112.112.112#dns.quad9.net"
    "2620:fe::fe#dns.quad9.net"
  ];
  services.resolved = {
    enable = true;
    settings.Resolve = {
      DNSOverTLS = true;
      DNSSEC = "allow-downgrade";
      FallbackDNS = [ ];
      LLMNR = false;
      MulticastDNS = false;
    };
  };

  # Authenticated time over NTS.
  services.chrony = {
    enable = true;
    enableNTS = true;
    servers = [ "time.cloudflare.com" "nts.netnod.se" "ptbtime1.ptb.de" ];
  };
}
