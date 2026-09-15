# Per-app GPU clock policy. gpu-perf.nix pins the card at RP1 (600 MHz on
# the A770) because VRM switching noise at high clocks couples into the
# DP/eARC chain and comes out of the speakers. That matters while audio is
# the point — nixlymedia and GeForce NOW keep RP1. RetroArch and Steam get
# the full range instead: shaders at 4K have nothing to do with 600 MHz.
#
# The floor stays at RP1 in both modes; it is what killed the deep-idle
# clock oscillation gpu-perf.nix was written for.
#
# The knobs are made group-writable so the caller needs no root and no
# systemd round-trip — a workspace switch must land within a frame.
{ pkgs, lib, config, ... }:

let
  gpuClock = pkgs.writeShellScriptBin "htpc-gpu-clock" ''
    set -u
    case "''${1:-}" in
      steam|retroarch) mode=high ;;
      *)               mode=low  ;;
    esac

    for card in /sys/class/drm/card*; do
      [ -e "$card/gt_max_freq_mhz" ] || continue
      rp0=$(cat "$card/gt_RP0_freq_mhz" 2>/dev/null) || continue
      rp1=$(cat "$card/gt_RP1_freq_mhz" 2>/dev/null) || continue

      # Floor first: max may never drop below min.
      echo "$rp1" > "$card/gt_min_freq_mhz" 2>/dev/null || true
      if [ "$mode" = high ]; then
        echo "$rp0" > "$card/gt_max_freq_mhz" 2>/dev/null || true
        echo "$rp0" > "$card/gt_boost_freq_mhz" 2>/dev/null || true
      else
        echo "$rp1" > "$card/gt_max_freq_mhz" 2>/dev/null || true
        echo "$rp1" > "$card/gt_boost_freq_mhz" 2>/dev/null || true
      fi
    done
  '';

  perms = pkgs.writeShellScript "htpc-gpu-clock-perms" ''
    for f in /sys/class/drm/card*/gt_min_freq_mhz \
             /sys/class/drm/card*/gt_max_freq_mhz \
             /sys/class/drm/card*/gt_boost_freq_mhz; do
      [ -e "$f" ] || continue
      ${pkgs.coreutils}/bin/chgrp users "$f" 2>/dev/null || true
      ${pkgs.coreutils}/bin/chmod 0664 "$f" 2>/dev/null || true
    done
  '';
in
lib.mkIf (config.nixlyos.mode == "htpc") {
  environment.systemPackages = [ gpuClock ];

  systemd.services.htpc-gpu-clock-perms = {
    description = "Make GPU clock knobs writable for the users group";
    wantedBy = [ "multi-user.target" ];
    after = [ "htpc-gpu-clocks.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${perms}";
    };
  };

  # A late-probing card would otherwise keep root-only knobs.
  services.udev.extraRules = ''
    ACTION=="add|change", SUBSYSTEM=="drm", KERNEL=="card[0-9]*", RUN+="${pkgs.systemd}/bin/systemctl --no-block restart htpc-gpu-clock-perms.service"
  '';
}
