{ config, lib, pkgs, nixlyUser, ... }:

let
  stack = {
    boot.kernelModules = [
      # iwlwifi may silently skip it.
      "iwlmvm"
    ];

    boot.kernel.sysctl = {
      "net.core.rmem_default" = 4194304;
      "net.core.wmem_default" = 4194304;
      "net.core.rmem_max" = 134217728;
      "net.core.wmem_max" = 134217728;
      "net.ipv4.tcp_rmem" = "4096 262144 134217728";
      "net.ipv4.tcp_wmem" = "4096 262144 134217728";
      "net.core.optmem_max" = 65536;

      # Least bufferbloat, highest throughput.
      "net.core.default_qdisc" = "cake";

      "net.ipv4.tcp_mtu_probing" = 1;
      "net.ipv4.tcp_fastopen" = 3;
      "net.ipv4.tcp_ecn" = 1;
      "net.ipv4.tcp_sack" = 1;
      "net.ipv4.tcp_dsack" = 1;
      "net.ipv4.tcp_window_scaling" = 1;
      "net.ipv4.tcp_timestamps" = 1;
      "net.ipv4.tcp_notsent_lowat" = 131072;
      "net.ipv4.tcp_slow_start_after_idle" = 0;

      # Dead peers found in 2 min.
      "net.ipv4.tcp_keepalive_time" = 60;
      "net.ipv4.tcp_keepalive_intvl" = 10;
      "net.ipv4.tcp_keepalive_probes" = 6;

      "net.ipv4.tcp_tw_reuse" = 1;
      "net.ipv4.tcp_fin_timeout" = 10;
      "net.ipv4.tcp_max_syn_backlog" = 8192;

      "net.core.somaxconn" = 4096;
      "net.core.netdev_max_backlog" = 250000;
      "net.core.netdev_budget" = 600;
      "net.core.netdev_budget_usecs" = 8000;

      "net.ipv4.ip_local_port_range" = "10240 65535";

      # QUIC and game traffic.
      "net.ipv4.udp_rmem_min" = 16384;
      "net.ipv4.udp_wmem_min" = 16384;

      "net.core.rps_sock_flow_entries" = 32768;
    };

    services.resolved = {
      enable = true;
      settings.Resolve = {
        # Validation blocked legitimate domains.
        DNSSEC = "false";
        # Strict breaks captive portals.
        DNSOverTLS = "opportunistic";
        FallbackDNS = [
          "1.1.1.1#cloudflare-dns.com"
          "1.0.0.1#cloudflare-dns.com"
          "9.9.9.9#dns.quad9.net"
        ];
        LLMNR = "false";
      };
    };

    # DHCP resolvers are ignored.
    networking.nameservers = [
      "9.9.9.9#dns.quad9.net"
      "149.112.112.112#dns.quad9.net"
    ];

    # nixlytile drives wpa_supplicant.
    networking.useDHCP = false;
    networking.useNetworkd = true;
    systemd.network.enable = true;
    systemd.network.networks."40-wired" = {
      matchConfig.Name = "en* eth*";
      networkConfig.DHCP = "yes";
      dhcpV4Config.RouteMetric = 100;
      linkConfig.RequiredForOnline = "no";
    };
    # Phone tethering, behind ethernet.
    systemd.network.networks."42-usb" = {
      matchConfig.Name = "usb*";
      networkConfig.DHCP = "yes";
      dhcpV4Config.RouteMetric = 200;
      linkConfig.RequiredForOnline = "no";
    };
    systemd.network.networks."45-wifi" = {
      matchConfig.Name = "wl*";
      networkConfig.DHCP = "yes";
      dhcpV4Config.RouteMetric = 600;
      linkConfig.RequiredForOnline = "no";
    };
    systemd.network.wait-online.enable = false;

    networking.wireless = {
      enable = true;
      userControlled = true;
      # Popup-saved networks land here.
      allowAuxiliaryImperativeNetworks = true;
      scanOnLowSignal = false;
      extraConfig = ''
        disable_scan_offload=1
      '';
    };

    # Stable IPv6 address.
    networking.tempAddresses = "disabled";

    # AX210 crashes on 6 GHz.
    boot.extraModprobeConfig = ''
      options iwlwifi bt_coex_active=N power_save=0 11n_disable=8 disable_11ax=1
      options iwlmvm power_scheme=1
    '';

    environment.systemPackages = with pkgs; [
      iproute2
      iptables
      nftables
    ];
  };

  # Cake both ways, rate from speedtest.
  shaping =
    let
      cfg = config.nixlyos.net;
      num = v: lib.optionalString (v != null) (toString v);

      shape = pkgs.writeShellScript "nixly-shape" ''
        set -u
        TC=${pkgs.iproute2}/bin/tc
        IP=${pkgs.iproute2}/bin/ip

        for path in /sys/class/net/*; do
          IF=$(${pkgs.coreutils}/bin/basename "$path")
          case "$IF" in en*|eth*|wl*|usb*) ;; *) continue ;; esac

          down="${num cfg.wanDownMbit}"
          up="${num cfg.wanUpMbit}"

          # Measured rate beats the guess.
          if [ -r "/var/lib/nixly-shape/$IF" ]; then
            DOWN=""; UP=""
            . "/var/lib/nixly-shape/$IF"
            [ -n "$DOWN" ] && down="$DOWN"
            [ -n "$UP" ] && up="$UP"
          fi
          [ -n "$down" ] && [ -n "$up" ] || continue

          $TC qdisc replace dev "$IF" root cake \
            bandwidth "$up"Mbit diffserv4 ack-filter nat || continue

          ifb="ifb-$IF"
          $IP link show "$ifb" >/dev/null 2>&1 || $IP link add "$ifb" type ifb || continue
          $IP link set "$ifb" up
          $TC qdisc del dev "$IF" handle ffff: ingress 2>/dev/null || true
          $TC qdisc add dev "$IF" handle ffff: ingress
          $TC filter add dev "$IF" parent ffff: protocol all prio 10 matchall \
            action mirred egress redirect dev "$ifb"
          $TC qdisc replace dev "$ifb" root cake \
            bandwidth "$down"Mbit besteffort nat ingress
        done
      '';

      # Link must be unshaped while measuring.
      measure = pkgs.writeShellScript "nixly-speedtest" ''
        set -u
        export PATH=${lib.makeBinPath (with pkgs; [
          coreutils
          gawk
          iproute2
          jq
          speedtest-go
          systemd
        ])}

        systemctl is-active -q gfn-focus.service && exit 0
        systemctl is-active -q nixly-gametune.service && exit 0

        route=$(ip -o route get 1.1.1.1 2>/dev/null) || exit 0
        IF=$(echo "$route" | awk '{for (i=1;i<NF;i++) if ($i=="dev") print $(i+1)}')
        SRC=$(echo "$route" | awk '{for (i=1;i<NF;i++) if ($i=="src") print $(i+1)}')
        [ -n "$IF" ] && [ -n "$SRC" ] || exit 0

        # Shaping returns on any exit.
        trap 'systemctl restart nixly-shape.service' EXIT

        tc qdisc del dev "$IF" root 2>/dev/null || true
        tc qdisc del dev "$IF" handle ffff: ingress 2>/dev/null || true

        json=$(speedtest-go --json --source "$SRC" 2>/dev/null) || exit 0
        dl=$(echo "$json" | jq -r '.servers[0].dl_speed // empty')
        ul=$(echo "$json" | jq -r '.servers[0].ul_speed // empty')
        [ -n "$dl" ] && [ -n "$ul" ] || exit 0

        # Bytes/s to Mbit, 94 %.
        down=$(echo "$dl" | awk '{printf "%d", $1 * 8 / 1000000 * 0.94}')
        up=$(echo "$ul" | awk '{printf "%d", $1 * 8 / 1000000 * 0.94}')

        # Keep the old file on nonsense.
        [ "$down" -ge 5 ] && [ "$up" -ge 5 ] || exit 0
        [ "$down" -le 10000 ] && [ "$up" -le 10000 ] || exit 0

        printf 'DOWN=%s\nUP=%s\n' "$down" "$up" > "/var/lib/nixly-shape/$IF"
      '';
    in
    {
      options.nixlyos.net = {
        wanDownMbit = lib.mkOption {
          type = lib.types.nullOr lib.types.ints.positive;
          default = null;
          example = 940;
          description = "Downlink fallback until speedtest.nix has measured this link.";
        };

        wanUpMbit = lib.mkOption {
          type = lib.types.nullOr lib.types.ints.positive;
          default = null;
          example = 940;
          description = "Uplink fallback until speedtest.nix has measured this link.";
        };

        autoMeasure = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Measure the WAN rate at boot instead of trusting wanDownMbit/wanUpMbit.";
        };
      };

      config = lib.mkMerge [
        {
          boot.kernelModules = [ "ifb" "sch_cake" "act_mirred" ];
          # The script names one per link.
          boot.extraModprobeConfig = "options ifb numifbs=0";

          systemd.services.nixly-shape = {
            description = "cake WAN shaping on every link";
            wantedBy = [ "multi-user.target" ];
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              ExecStart = "${shape}";
              StateDirectory = "nixly-shape";
            };
          };

          services.udev.extraRules = ''
            SUBSYSTEM=="net", ACTION=="add", RUN+="${pkgs.systemd}/bin/systemctl --no-block restart nixly-shape.service"
          '';
        }

        (lib.mkIf cfg.autoMeasure {
          systemd.services.nixly-speedtest = {
            description = "Measure WAN rate for cake shaping";
            # 300 MB of radio time.
            unitConfig.ConditionACPower = true;
            after = [ "network-online.target" ];
            wants = [ "network-online.target" ];
            serviceConfig = {
              Type = "oneshot";
              ExecStart = "${measure}";
              StateDirectory = "nixly-shape";
              TimeoutStartSec = "5min";
            };
          };

          systemd.timers.nixly-speedtest = {
            wantedBy = [ "timers.target" ];
            timerConfig = {
              # After boot owns the line.
              OnBootSec = "90s";
              Persistent = false;
            };
          };
        })
      ];
    };

  # EEE and coalescing cost latency.
  latency =
    let
      tune = pkgs.writeShellScript "nixly-niclat" ''
        set -u
        ETHTOOL=${pkgs.ethtool}/bin/ethtool

        ncpu=$(${pkgs.coreutils}/bin/nproc)
        [ "$ncpu" -gt 32 ] && ncpu=32
        mask=$(printf '%x' $(( (1 << ncpu) - 1 )))

        for path in /sys/class/net/*; do
          IF=$(${pkgs.coreutils}/bin/basename "$path")
          case "$IF" in en*|eth*|wl*) ;; *) continue ;; esac

          $ETHTOOL --set-eee "$IF" eee off 2>/dev/null || true
          $ETHTOOL -C "$IF" adaptive-rx off rx-usecs 0 2>/dev/null || true

          # Covers non-Intel WiFi too.
          ${pkgs.iw}/bin/iw dev "$IF" set power_save off 2>/dev/null || true

          queues=$(ls -d "$path"/queues/rx-* 2>/dev/null | wc -l)
          if [ "$queues" = 1 ]; then
            echo 32768 > "$path/queues/rx-0/rps_flow_cnt" 2>/dev/null || true
            echo "$mask" > "$path/queues/rx-0/rps_cpus" 2>/dev/null || true
          fi
        done
      '';
    in
    {
      systemd.services.nixly-niclat = {
        description = "Latency tuning per network link (EEE, coalescing, RFS)";
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${tune}";
        };
      };

      services.udev.extraRules = ''
        SUBSYSTEM=="net", ACTION=="add", RUN+="${pkgs.systemd}/bin/systemctl --no-block restart nixly-niclat.service"
      '';
    };

  vpn = {
    boot.kernelModules = [
      "af_key"
      "ah4"
      "ah6"
      "esp4"
      "esp6"
      "xfrm_user"
      "xfrm_algo"
      "l2tp_core"
      "l2tp_netlink"
      "l2tp_ppp"
      "nf_conntrack_pptp"
      "nf_nat_pptp"
      "tun"
      "wireguard"
    ];

    environment.systemPackages = with pkgs; [
      openvpn
      wireguard-tools
      openconnect
      vpnc
      sstp
      strongswan
      libreswan
      openfortivpn
      (writeShellScriptBin "tailscale-init" ''
        set -e
        sudo systemctl start tailscaled
        sudo tailscale up --ssh
        until [ "$(tailscale status --json 2>/dev/null | ${jq}/bin/jq -r .BackendState)" = "Running" ]; do
          sleep 1
        done
        ip=$(tailscale ip -4 2>/dev/null | head -1)
        echo ""
        echo "Tailscale aktiv ($ip). Venter paa at LAN-ssh stenges..."
        for _ in $(seq 30); do
          sudo ${nftables}/bin/nft list chain inet nixos-fw input-allow 2>/dev/null \
            | grep -q 'tcp dport 22 accept' || break
          sleep 1
        done
        echo "SSH stengt for LAN/internett — naas naa kun via tailnettet:"
        echo "  ssh total@$(hostname)   # fra enhver tailnet-enhet, uten noekkel/passord"
        echo "Aktive ssh-oekter overlever; nye maa gaa via tailscale."
      '')
    ];

    services.strongswan = {
      enable = true;
      secrets = [ "/etc/ipsec.secrets" ];
    };

    # Tailscale SSH needs no keys.
    services.tailscale = {
      enable = true;
      extraUpFlags = [ "--ssh" ];
    };

    # Login once with netbird up.
    services.netbird.enable = true;

    # Started by hand, never at boot.
    systemd.services.strongswan.wantedBy = lib.mkForce [ ];
    systemd.services.tailscaled.wantedBy = lib.mkForce [ ];
    systemd.services.netbird.wantedBy = lib.mkForce [ ];

    networking.firewall.trustedInterfaces = [ "tailscale0" "wt0" ];

    # Wheel toggles VPN units.
    security.polkit.extraConfig = ''
      polkit.addRule(function(action, subject) {
        if (!subject.isInGroup("wheel"))
          return polkit.Result.NOT_HANDLED;
        // Start and stop, per unit.
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
        // Unit files lack a name.
        if (action.id == "org.freedesktop.systemd1.manage-unit-files" ||
            action.id == "org.freedesktop.systemd1.reload-daemon") {
          return polkit.Result.YES;
        }
        return polkit.Result.NOT_HANDLED;
      });
    '';
  };

  ssh = {
    # Private ranges only.
    networking.firewall.extraInputRules = ''
      ip saddr { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16 } tcp dport 22 accept
    '';

    services.openssh = {
      enable = true;
      openFirewall = false;
      settings = {
        PermitRootLogin = "no";
        PasswordAuthentication = true;
        PermitEmptyPasswords = false;
        KbdInteractiveAuthentication = false;
        PubkeyAuthentication = true;
        AllowUsers = [ nixlyUser ];
        X11Forwarding = false;
        AllowTcpForwarding = "yes";
        # Remote hosts never use local keys.
        AllowAgentForwarding = "no";
        MaxSessions = 4;
        MaxStartups = "3:50:10";
        UseDns = false;
        ClientAliveInterval = 30;
        ClientAliveCountMax = 3;
        MaxAuthTries = 3;
        LoginGraceTime = "20s";
        Compression = "no";
        KexAlgorithms = [
          "sntrup761x25519-sha512@openssh.com"
          "curve25519-sha256"
          "curve25519-sha256@libssh.org"
        ];
        Ciphers = [
          "chacha20-poly1305@openssh.com"
          "aes256-gcm@openssh.com"
          "aes256-ctr"
        ];
        Macs = [
          "hmac-sha2-512-etm@openssh.com"
          "hmac-sha2-256-etm@openssh.com"
        ];
      };
    };

    programs.ssh = {
      startAgent = false;
      extraConfig = ''
        Host *
          ServerAliveInterval 20
          ServerAliveCountMax 3
          AddKeysToAgent yes
          ForwardAgent no
      '';
    };
  };

  nfs =
    let
      nfsOptions = lib.concatStringsSep "," [
        "rw"
        "vers=4.2"
        "rsize=1048576"
        "wsize=1048576"
        "nconnect=8"
        "soft"
        "timeo=5"
        "retrans=2"
        "retry=0"
        "fsc"
        "acl"
        "noatime"
        "nodiratime"
        "tcp"
        "lookupcache=all"
        "actimeo=300"
        "nocto"
      ];

      share = name: {
        what = "10.0.0.8:/${lib.toLower name}";
        where = "/mnt/nfs/${name}";
        type = "nfs";
        mountConfig = {
          Options = nfsOptions;
          TimeoutSec = "5s";
        };
        requires = [ "nfs-bigdisk1-check.service" ];
        after = [ "nfs-bigdisk1-check.service" "network-online.target" ];
        wants = [ "network-online.target" ];
        unitConfig = {
          StartLimitIntervalSec = 0;
        };
      };

      # Unmounting drops every cache.
      automount = name: {
        where = "/mnt/nfs/${name}";
        automountConfig = {
          TimeoutIdleSec = 0;
        };
        wantedBy = [ "multi-user.target" ];
      };

      shares = [ "Bigdisk1" "Bigdisk2" ];
    in
    {
      boot.supportedFilesystems = [ "nfs" ];

      # Only NFSv3 needs it.
      services.rpcbind.enable = lib.mkForce false;

      services.cachefilesd = {
        enable = true;
        extraConfig = ''
          brun 20%
          bcull 10%
          bstop 5%
          frun 20%
          fcull 10%
          fstop 5%
        '';
      };

      systemd.tmpfiles.rules = [
        "d /mnt/nfs 0755 root root -"
        "d /mnt/nfs/Bigdisk1 0755 root root -"
        "d /mnt/nfs/Bigdisk2 0755 root root -"
      ];

      # Fails in a second, never blocks.
      systemd.services.nfs-bigdisk1-check = {
        description = "Check NFS server 10.0.0.8 reachability";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${pkgs.bash}/bin/bash -c '${pkgs.iputils}/bin/ping -c 1 -W 1 10.0.0.8 > /dev/null 2>&1'";
        };
        unitConfig = {
          StartLimitIntervalSec = 0;
        };
      };

      systemd.mounts = map share shares;
      systemd.automounts = map automount shares;

      # statfs keeps connections warm.
      systemd.services.nfs-keepalive = {
        description = "Keep NFS mounts mounted and their connections warm";
        wantedBy = [ "multi-user.target" ];
        after = [ "remote-fs.target" ];
        serviceConfig = {
          ExecStart = pkgs.writeShellScript "nfs-keepalive" ''
            while :; do
              for d in /mnt/nfs/*; do
                ${pkgs.coreutils}/bin/stat -f "$d" > /dev/null 2>&1 &
              done
              wait
              ${pkgs.coreutils}/bin/sleep 30
            done
          '';
          Restart = "always";
        };
      };

      # One rsize measured fastest.
      systemd.services.nfs-readahead = {
        description = "Raise NFS readahead to one rsize (1 MB)";
        after = [ "mnt-nfs-Bigdisk1.mount" "mnt-nfs-Bigdisk2.mount" ];
        wantedBy = [ "mnt-nfs-Bigdisk1.mount" "mnt-nfs-Bigdisk2.mount" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = pkgs.writeShellScript "nfs-readahead" ''
            set -u
            # Third mountinfo field is maj:min.
            while read -r _ _ majmin _ _ _ rest; do
              case "$rest" in
                *" nfs "*|*" nfs4 "*) ;;
                *) continue ;;
              esac
              f=/sys/class/bdi/$majmin/read_ahead_kb
              [ -w "$f" ] && echo 1024 > "$f"
            done < /proc/self/mountinfo
            exit 0
          '';
        };
      };
    };
in
{
  imports = [
    stack
    shaping
    latency
    vpn
    ssh
    nfs
  ];
}
