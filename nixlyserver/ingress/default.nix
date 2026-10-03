# Allowed countries; no VPN, hosting, Tor.
{ config, lib, pkgs, ... }:

let
  table = "ingress";
  stateDir = "nixlyserver-ingress";
  sshPorts = lib.concatMapStringsSep ", " toString config.services.openssh.ports;
  private4 = "10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 169.254.0.0/16";
  private6 = "fe80::/10, fc00::/7";

  fetch = pkgs.writeShellApplication {
    name = "nixlyserver-ingress-fetch";
    runtimeInputs = with pkgs; [ curl gawk coreutils gnugrep ];
    text = builtins.readFile ./fetch.sh;
  };
in
{
  networking.nftables.tables.${table} = {
    family = "inet";
    content = ''
      set allowed4 { type ipv4_addr; flags interval; }
      set denied4 { type ipv4_addr; flags interval; auto-merge; }
      set banned4 { type ipv4_addr; flags timeout; timeout 1h; }
      set banned6 { type ipv6_addr; flags timeout; timeout 1h; }
      set ssh4 { type ipv4_addr; flags dynamic, timeout; timeout 1m; }
      set ssh6 { type ipv6_addr; flags dynamic, timeout; timeout 1m; }

      chain prerouting {
        type filter hook prerouting priority mangle; policy accept;
        ct state invalid drop
        ct state established,related accept
        iif lo accept
        iifname "tailscale0" accept
        ip saddr @banned4 drop
        ip6 saddr @banned6 drop
        tcp dport { ${sshPorts} } update @ssh4 { ip saddr limit rate over 6/minute burst 6 packets } add @banned4 { ip saddr } drop
        tcp dport { ${sshPorts} } update @ssh6 { ip6 saddr limit rate over 6/minute burst 6 packets } add @banned6 { ip6 saddr } drop
        ip saddr { ${private4} } accept
        ip6 saddr { ${private6} } accept
        icmpv6 type { nd-neighbor-solicit, nd-neighbor-advert, nd-router-advert } ip6 hoplimit 255 accept
        meta nfproto ipv6 drop
        ip saddr != @allowed4 drop
        ip saddr @denied4 drop
      }
    '';
  };

  # Atomic load; empty means closed.
  networking.nftables.ruleset = ''
    include "/var/lib/${stateDir}/lists/*.nft"
  '';

  systemd.services.nixlyserver-ingress = {
    description = "Refresh country and VPN lists for the ingress gate";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    environment = {
      COUNTRIES = lib.concatStringsSep " " config.nixlyserver.allowedCountries;
      TABLE = table;
    };
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${fetch}/bin/nixlyserver-ingress-fetch";
      ExecStartPost = "+${pkgs.systemd}/bin/systemctl reload nftables.service";
      DynamicUser = true;
      StateDirectory = stateDir;
      StateDirectoryMode = "0755";
      CapabilityBoundingSet = "";
      NoNewPrivileges = true;
      PrivateDevices = true;
      PrivateUsers = true;
      ProtectHome = true;
      ProtectClock = true;
      ProtectHostname = true;
      ProtectKernelLogs = true;
      ProtectKernelModules = true;
      ProtectKernelTunables = true;
      ProtectControlGroups = true;
      ProtectProc = "invisible";
      ProcSubset = "pid";
      RestrictAddressFamilies = [ "AF_UNIX" "AF_INET" "AF_INET6" ];
      RestrictNamespaces = true;
      RestrictRealtime = true;
      LockPersonality = true;
      MemoryDenyWriteExecute = true;
      SystemCallArchitectures = "native";
      SystemCallFilter = [ "@system-service" "~@privileged" "~@resources" ];
      UMask = "0022";
    };
  };

  systemd.timers.nixlyserver-ingress = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "1min";
      OnCalendar = "daily";
      RandomizedDelaySec = "10min";
      Persistent = true;
    };
  };
}
