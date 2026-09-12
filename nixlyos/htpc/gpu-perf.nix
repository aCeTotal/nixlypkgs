# Arc A770 clock pinning. i915's GuC SLPC scales GPU frequency on
# utilisation, and emulator + XMB loads are light enough that the card
# sits at idle clocks for minutes (slow games/menus), ramps up (fast),
# then drops again once utilisation falls — the oscillation repeats.
# Pin min = boost = max (RP0) so the GPU never leaves full clock; the
# box is mains-powered so the idle-watt cost is accepted. Runtime PM is
# also forced on for the card: perf.nix sets pci power/control=auto
# globally for the laptop battery budget, which does not belong on the
# HTPC's display adapter.
{ pkgs, lib, config, ... }:

lib.mkIf (config.nixlyos.mode == "htpc") {
  systemd.services.htpc-gpu-clocks = {
    description = "Pin Intel Arc GPU clocks to max (RP0)";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "htpc-gpu-clocks" ''
        set -u
        for card in /sys/class/drm/card*; do
          [ -e "$card/gt_RP0_freq_mhz" ] || continue
          rp0=$(cat "$card/gt_RP0_freq_mhz")
          # max first: min may never exceed max.
          echo "$rp0" > "$card/gt_max_freq_mhz"   || true
          echo "$rp0" > "$card/gt_boost_freq_mhz" || true
          echo "$rp0" > "$card/gt_min_freq_mhz"   || true
        done
        # Display-class PCI devices (0x03xxxx): keep runtime PM off.
        for dev in /sys/bus/pci/devices/*; do
          case "$(cat "$dev/class")" in
            0x03*) echo on > "$dev/power/control" || true ;;
          esac
        done
      '';
    };
  };
}
