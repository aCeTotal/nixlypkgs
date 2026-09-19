{ ... }:

{
  # dcspitd serves web surfaces to tablets and phones over the tailnet.
  # No LAN ports are opened; the trusted tailscale0 interface reaches 8080
  # and 5353, so a device on the same WiFi cannot touch it.
  networking.hosts."127.0.0.1" = [ "dcspit.local" ];
}
