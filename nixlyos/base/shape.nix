# WAN shaping with cake, both directions. Without a bandwidth figure cake
# cannot move the bottleneck off the ISP's buffer, so the queue that adds
# latency lives in the modem and no local qdisc can touch it. Egress runs
# diffserv4 so the EF marks from geforce-now/qos.nix reach the voice tin;
# ingress is mirrored into an ifb and shaped besteffort, since DSCP set by
# a remote is not trustworthy. The rate per link comes from speedtest.nix
# (/var/lib/nixly-shape/<iface>), falling back to the options below and
# then to no shaping at all — the old behaviour.
# On WiFi this replaces mac80211's fq root qdisc: correct while the WAN is
# the bottleneck, wrong if the air link drops below the measured rate.
{ config, lib, pkgs, ... }:

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

      # A measured rate always wins over the configured guess.
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
in
{
  options.nixlyos.net.wanDownMbit = lib.mkOption {
    type = lib.types.nullOr lib.types.ints.positive;
    default = null;
    example = 940;
    description = "Downlink fallback until speedtest.nix has measured this link.";
  };

  options.nixlyos.net.wanUpMbit = lib.mkOption {
    type = lib.types.nullOr lib.types.ints.positive;
    default = null;
    example = 940;
    description = "Uplink fallback until speedtest.nix has measured this link.";
  };

  config = {
    boot.kernelModules = [ "ifb" "sch_cake" "act_mirred" ];
    # No auto-created ifb0/ifb1; the script names one per link.
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

    # Hotplugged NIC gets the same treatment.
    services.udev.extraRules = ''
      SUBSYSTEM=="net", ACTION=="add", RUN+="${pkgs.systemd}/bin/systemctl --no-block restart nixly-shape.service"
    '';
  };
}
