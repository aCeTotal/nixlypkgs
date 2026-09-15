# Per-link latency knobs the driver defaults get wrong for streaming.
# EEE parks the PHY between frames and pays a wake latency on every burst;
# adaptive interrupt coalescing trades the same latency for CPU. RFS is
# only wired up for single-queue links (WiFi): a multiqueue NIC already
# steers with RSS, and forcing RPS there just adds IPIs.
{ pkgs, ... }:

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

      # Generic; the iwlwifi modprobe flag covers only Intel.
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
}
