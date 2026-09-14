# Arc A770 clock pin. i915's GuC SLPC scales GPU frequency on
# utilisation, and emulator + XMB loads are light enough that the card
# sits at idle clocks for minutes (slow games/menus), ramps up (fast),
# then drops again once utilisation falls — the oscillation repeats.
# Pin min = max = boost = RP1 (efficient clock): the floor kills the
# deep-idle oscillation, and the cap keeps the card out of the high
# voltage/frequency bins entirely. VRM switching noise at boost clocks
# couples electrically into the DP cable and comes out audibly on the
# TV/eARC chain (verified by ear 2026-09-14: noise tracked the clock,
# died at low clock) — with max = RP0 every render burst during
# playback re-injected it whenever the amp was open. RC6 still parks
# the GPU between frames. Video decode is fixed-function and needs
# nothing near RP0; if a heavy game needs more, raise max/boost to a
# mid clock (e.g. 1400) and re-check by ear. Runtime PM is also forced
# on for the card: perf.nix sets pci power/control=auto globally for
# the laptop battery budget, which does not belong on the HTPC's
# display adapter.
{ pkgs, lib, config, ... }:

lib.mkIf (config.nixlyos.mode == "htpc") {
  systemd.services.htpc-gpu-clocks = {
    description = "Pin Intel Arc GPU clocks at RP1 (VRM noise on TV/eARC above)";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "htpc-gpu-clocks" ''
        set -u
        # Wait for i915 to expose the freq knobs: as a plain oneshot this
        # raced module init on fast boots — the glob matched nothing, the
        # service "succeeded", and the GPU spent the whole session on
        # SLPC's utilisation scaling (idle clocks in menus/light emu
        # loads = the fresh-boot slowness, until a heavy app happened to
        # ramp it).
        pinned=0
        for _ in $(seq 60); do
          for card in /sys/class/drm/card*; do
            [ -e "$card/gt_RP0_freq_mhz" ] || continue
            rp1=$(cat "$card/gt_RP1_freq_mhz")
            # min first: on a rebuild min may already sit at RP1, and
            # max may never drop below min.
            echo "$rp1" > "$card/gt_min_freq_mhz"   || true
            echo "$rp1" > "$card/gt_max_freq_mhz"   || true
            echo "$rp1" > "$card/gt_boost_freq_mhz" || true
            pinned=1
          done
          [ "$pinned" = 1 ] && break
          sleep 1
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
