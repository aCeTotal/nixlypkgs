# Measures the WAN rate at boot and hands it to shape.nix as
# /var/lib/nixly-shape/<iface>. Two things make or break this: the link must
# be unshaped while measuring (otherwise every boot measures the previous
# cap and the rate ratchets down), and it must never run during a stream.
# The result is bound to one interface — cable and WiFi have nothing in
# common — so each link gets its own file the first time it carries the
# default route. Costs ~300 MB of traffic per boot.
{ config, lib, pkgs, ... }:

let
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

    # Shaping back on whatever happens below.
    trap 'systemctl restart nixly-shape.service' EXIT

    tc qdisc del dev "$IF" root 2>/dev/null || true
    tc qdisc del dev "$IF" handle ffff: ingress 2>/dev/null || true

    json=$(speedtest-go --json --source "$SRC" 2>/dev/null) || exit 0
    dl=$(echo "$json" | jq -r '.servers[0].dl_speed // empty')
    ul=$(echo "$json" | jq -r '.servers[0].ul_speed // empty')
    [ -n "$dl" ] && [ -n "$ul" ] || exit 0

    # speedtest-go reports bytes/s; 94 % leaves cake its headroom.
    down=$(echo "$dl" | awk '{printf "%d", $1 * 8 / 1000000 * 0.94}')
    up=$(echo "$ul" | awk '{printf "%d", $1 * 8 / 1000000 * 0.94}')

    # A bad server returns nonsense; the previous file is better than that.
    [ "$down" -ge 5 ] && [ "$up" -ge 5 ] || exit 0
    [ "$down" -le 10000 ] && [ "$up" -le 10000 ] || exit 0

    printf 'DOWN=%s\nUP=%s\n' "$down" "$up" > "/var/lib/nixly-shape/$IF"
  '';
in
{
  options.nixlyos.net.autoMeasure = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Measure the WAN rate at boot instead of trusting wanDownMbit/wanUpMbit.";
  };

  config = lib.mkIf config.nixlyos.net.autoMeasure {
    systemd.services.nixly-speedtest = {
      description = "Measure WAN rate for cake shaping";
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
        # Late enough that boot and the first app own the line first.
        OnBootSec = "90s";
        Persistent = false;
      };
    };
  };
}
