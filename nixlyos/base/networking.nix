{
  config,
  lib,
  pkgs,
  ...
}:

{
  # Networking and VPN kernel modules.
  boot.kernelModules = [
    "tcp_bbr"
    # IPsec/IKEv2
    "af_key"
    "ah4"
    "ah6"
    "esp4"
    "esp6"
    "xfrm_user"
    "xfrm_algo"
    # L2TP
    "l2tp_core"
    "l2tp_netlink"
    "l2tp_ppp"
    # PPTP
    "nf_conntrack_pptp"
    "nf_nat_pptp"
    # TUN/TAP for OpenVPN
    "tun"
    # WireGuard
    "wireguard"
    # Forced: iwlwifi's request_module("iwlmvm") can fail silently, leaving no wlan0.
    "iwlmvm"
  ];

  boot.kernel.sysctl = {
    # Socket buffer sizes (auto-tuned within these caps).
    "net.core.rmem_default" = 4194304;
    "net.core.wmem_default" = 4194304;
    "net.core.rmem_max" = 134217728;
    "net.core.wmem_max" = 134217728;
    "net.ipv4.tcp_rmem" = "4096 262144 134217728";
    "net.ipv4.tcp_wmem" = "4096 262144 134217728";
    "net.core.optmem_max" = 65536;

    # BBR plus cake: least bufferbloat, highest throughput.
    "net.core.default_qdisc" = "cake";
    "net.ipv4.tcp_congestion_control" = "bbr";

    # TCP path/feature tuning.
    "net.ipv4.tcp_mtu_probing" = 1;
    "net.ipv4.tcp_fastopen" = 3; # client + server TFO
    "net.ipv4.tcp_ecn" = 1;
    "net.ipv4.tcp_sack" = 1;
    "net.ipv4.tcp_dsack" = 1;
    "net.ipv4.tcp_window_scaling" = 1;
    "net.ipv4.tcp_timestamps" = 1;

    # Send-side bufferbloat cap, lower latency for HTTP/2 and 3.
    "net.ipv4.tcp_notsent_lowat" = 131072;
    # Keep cwnd across keep-alive idle periods for faster resume.
    "net.ipv4.tcp_slow_start_after_idle" = 0;

    # Dead-connection detection: 60 s idle, 10 s probes, 6 tries.
    "net.ipv4.tcp_keepalive_time" = 60;
    "net.ipv4.tcp_keepalive_intvl" = 10;
    "net.ipv4.tcp_keepalive_probes" = 6;

    # Connection churn from browser parallel fetches.
    "net.ipv4.tcp_tw_reuse" = 1;
    "net.ipv4.tcp_fin_timeout" = 10;
    "net.ipv4.tcp_max_syn_backlog" = 8192;

    # Listen backlog and RX queue for high throughput.
    "net.core.somaxconn" = 4096;
    "net.core.netdev_max_backlog" = 250000;
    "net.core.netdev_budget" = 600;
    "net.core.netdev_budget_usecs" = 8000;

    # Local port pool, room for parallel HTTP connections.
    "net.ipv4.ip_local_port_range" = "10240 65535";

    # No busy_poll: it spins the CPU per blocking socket read for a gain that is
    # noise over WiFi.

    # UDP buffer minima, better for QUIC and game traffic.
    "net.ipv4.udp_rmem_min" = 16384;
    "net.ipv4.udp_wmem_min" = 16384;

    # Receive packet steering: spread RX across cores.
    "net.core.rps_sock_flow_entries" = 32768;
  };

  services.resolved = {
    enable = true;
    settings.Resolve = {
      # DNSSEC off: resolved's validation blocks legitimate domains.
      DNSSEC = "false";
      # DoT to Quad9; strict would break captive portals on open networks.
      DNSOverTLS = "opportunistic";
      FallbackDNS = [
        "1.1.1.1#cloudflare-dns.com"
        "1.0.0.1#cloudflare-dns.com"
        "9.9.9.9#dns.quad9.net"
      ];
      LLMNR = "false";
    };
  };

  # Quad9 as primary DNS; the DHCP-supplied resolver is ignored.
  networking.nameservers = [
    "9.9.9.9#dns.quad9.net"
    "149.112.112.112#dns.quad9.net"
  ];

  # Minimal kernel-adjacent stack: systemd-networkd for addressing/DHCP,
  # wpa_supplicant for WPA (driven by nixlytile over its control socket).
  # nixlytile itself renders the tray icons/popups and enforces the
  # wifi-off-while-ethernet policy via rfkill.
  networking.useDHCP = false;
  networking.useNetworkd = true;
  systemd.network.enable = true;
  systemd.network.networks."40-wired" = {
    matchConfig.Name = "en* eth*";
    networkConfig.DHCP = "yes";
    dhcpV4Config.RouteMetric = 100;
    linkConfig.RequiredForOnline = "no";
  };
  systemd.network.networks."45-wifi" = {
    matchConfig.Name = "wl*";
    networkConfig.DHCP = "yes";
    # Wired wins when both are up.
    dhcpV4Config.RouteMetric = 600;
    linkConfig.RequiredForOnline = "no";
  };
  systemd.network.wait-online.enable = false;

  networking.wireless = {
    enable = true;
    # nixlytile (wheel user) talks to the wpa_supplicant control socket.
    userControlled.enable = true;
    # Networks saved from the popup land in imperative.conf (update_config=1).
    allowAuxiliaryImperativeNetworks = true;
    scanOnLowSignal = false;
  };

  # VPN start/stop + autoconnect toggles from the nixlytile popup:
  # wheel may manage the VPN units without a password prompt.
  security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
      if (!subject.isInGroup("wheel"))
        return polkit.Result.NOT_HANDLED;
      // start/stop: manage-units carries the unit name as a detail
      if (action.id == "org.freedesktop.systemd1.manage-units") {
        var unit = action.lookup("unit");
        if (unit &&
            (unit.indexOf("wg-quick") == 0 ||
             unit.indexOf("openvpn-") == 0 ||
             unit.indexOf("openconnect-") == 0 ||
             unit.indexOf("openfortivpn-") == 0 ||
             unit.indexOf("strongswan") == 0 ||
             unit.indexOf("tailscaled") == 0)) {
          return polkit.Result.YES;
        }
      }
      // enable/disable: manage-unit-files has no unit detail, so it
      // cannot be scoped per-unit — wheel can sudo anyway
      if (action.id == "org.freedesktop.systemd1.manage-unit-files" ||
          action.id == "org.freedesktop.systemd1.reload-daemon") {
        return polkit.Result.YES;
      }
      return polkit.Result.NOT_HANDLED;
    });
  '';

  # IPv6 privacy extensions off, for a stable address.
  networking.tempAddresses = "disabled";

  # Works around an AX210 firmware crash on 6 GHz by dropping to 11ac.
  boot.extraModprobeConfig = ''
    options iwlwifi bt_coex_active=N power_save=0 11n_disable=8 disable_11ax=1
    options iwlmvm power_scheme=1
  '';

  # Spreads NIC IRQs across cores for steadier latency under load.
  services.irqbalance.enable = true;

  # StrongSwan for IKEv2/IPsec.
  services.strongswan = {
    enable = true;
    secrets = [ "/etc/ipsec.secrets" ];
  };

  environment.systemPackages = with pkgs; [
    # VPN clients
    openvpn
    wireguard-tools
    openconnect # Cisco AnyConnect compatible
    vpnc # Cisco VPN
    sstp
    strongswan # IKEv2/IPsec
    libreswan # Alternative IPsec
    openfortivpn # Fortinet

    iproute2
    iptables
    nftables
  ];
}
