# HTPC controller plumbing on top of apps/gaming.nix (xpadneo/xone, udev
# rules, bluez reconnect policy — all still active here):
#
#  1. htpc-bt-autopair: continuous discovery. Put a pad in pairing mode and
#     it is paired + trusted + connected automatically — no UI, no keyboard.
#  2. htpc-xone-recover: the Microsoft Xbox Wireless dongle sometimes comes
#     up dead at boot until it is re-plugged. A sysfs authorized-cycle IS a
#     re-plug, so the service detects an unbound dongle and replays one.
{ pkgs, lib, config, ... }:

let
  btAutopair = pkgs.writeShellScript "htpc-bt-autopair" ''
    set -u
    BT=${pkgs.bluez}/bin/bluetoothctl

    until "$BT" show | ${pkgs.gnugrep}/bin/grep -q "Powered: yes"; do
      sleep 2
    done
    "$BT" pairable on >/dev/null 2>&1 || true

    is_pad() { # $1 mac, $2 name — gamepad by bluez icon/appearance or name
      info=$("$BT" info "$1" 2>/dev/null) || return 1
      printf '%s' "$info" | ${pkgs.gnugrep}/bin/grep -qE \
        "Icon: input-gaming|Appearance: 0x03c" && return 0
      printf '%s' "$2" | ${pkgs.gnugrep}/bin/grep -qiE \
        "controller|gamepad|dualsense|dualshock|wireless gamepad|joy-con|8bitdo|xbox" \
        && return 0
      return 1
    }

    while :; do
      # Discovery in 12 s bursts: bluez drops discovery when the client
      # exits, so a fresh burst each lap keeps the scan effectively
      # continuous without holding a long-lived session.
      "$BT" --timeout 12 scan on >/dev/null 2>&1 || true

      paired=$("$BT" devices Paired 2>/dev/null | ${pkgs.gawk}/bin/awk '{print $2}')
      "$BT" devices 2>/dev/null | while read -r _ mac name; do
        [ -n "$mac" ] || continue
        printf '%s\n' "$paired" | ${pkgs.gnugrep}/bin/grep -qiF "$mac" && continue
        is_pad "$mac" "$name" || continue
        echo "pairing new controller: $name ($mac)"
        "$BT" pair "$mac" >/dev/null 2>&1 || continue
        "$BT" trust "$mac" >/dev/null 2>&1 || true
        "$BT" connect "$mac" >/dev/null 2>&1 || true
      done
      sleep 3
    done
  '';

  # 02fe = Xbox Wireless Adapter (xone), 0719 = the older Xbox 360 receiver.
  xoneRecover = pkgs.writeShellScript "htpc-xone-recover" ''
    set -u
    # Let the normal probe (driver bind + firmware load) finish first.
    sleep 8
    for try in 1 2 3; do
      fixed=1
      for dev in /sys/bus/usb/devices/*; do
        [ -f "$dev/idVendor" ] && [ -f "$dev/idProduct" ] || continue
        vid=$(cat "$dev/idVendor"); pid=$(cat "$dev/idProduct")
        [ "$vid" = "045e" ] || continue
        case "$pid" in 02fe|0719) ;; *) continue ;; esac
        # Healthy dongle: its interface is bound to an xone/xpad driver.
        bound=""
        for intf in "$dev":*/driver; do
          [ -e "$intf" ] || continue
          case "$(basename "$(readlink -f "$intf")")" in
            *xone*|xpad*) bound=1 ;;
          esac
        done
        if [ -z "$bound" ]; then
          echo "xone dongle at $dev unbound — software re-plug (try $try)"
          echo 0 > "$dev/authorized" 2>/dev/null || true
          sleep 2
          echo 1 > "$dev/authorized" 2>/dev/null || true
          fixed=0
        fi
      done
      [ "$fixed" = 1 ] && exit 0
      sleep 5
    done
    exit 0
  '';
in
lib.mkIf (config.nixlyos.mode == "htpc") {

  systemd.services.htpc-bt-autopair = {
    description = "Auto-pair any Bluetooth game controller in pairing mode";
    after = [ "bluetooth.service" ];
    wants = [ "bluetooth.service" ];
    wantedBy = [ "bluetooth.target" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${btAutopair}";
      Restart = "always";
      RestartSec = 5;
      Nice = 10;
    };
  };

  systemd.services.htpc-xone-recover = {
    description = "Re-plug a dead Xbox Wireless dongle via sysfs";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${xoneRecover}";
    };
  };

  # Hotplug: a dongle inserted (or re-enumerated) after boot gets the same
  # recovery check.
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="045e", ATTR{idProduct}=="02fe", TAG+="systemd", ENV{SYSTEMD_WANTS}+="htpc-xone-recover.service"
    ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="045e", ATTR{idProduct}=="0719", TAG+="systemd", ENV{SYSTEMD_WANTS}+="htpc-xone-recover.service"
  '';
}
