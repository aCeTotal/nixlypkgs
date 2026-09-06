{ lib, config, pkgs, ... }:

let
  kp = config.boot.kernelPackages;
  msiEcPkg = if kp ? msi-ec then kp.msi-ec else if kp ? msi_ec then kp.msi_ec else null;
  mccPkg = if pkgs ? mcontrolcenter then pkgs.mcontrolcenter else null;

  # Every EC firmware version msi-ec has a config for, extracted from the driver
  # source at build time.
  fwList = pkgs.runCommand "msi-ec-firmware-list" { } ''
    grep -ohE '"[0-9A-Z]+E[A-Z0-9]+\.[0-9]+"' ${msiEcPkg.src}/msi-ec.c \
      | tr -d '"' | sort -u > $out
  '';

  # msi-ec refuses to load on an unlisted EC firmware revision, so autodetection
  # is tried first and, failing that, the firmware is read and pinned to the
  # config for the same board and EMS number.
  autoload = pkgs.writeShellScript "msi-ec-autoload" ''
    set -u
    export PATH=${lib.makeBinPath [ pkgs.kmod pkgs.coreutils pkgs.gnugrep ]}

    if modprobe msi-ec 2>/dev/null && [ -d /sys/devices/platform/msi-ec ]; then
      echo "msi-ec: EC-firmware stoettet direkte"
      exit 0
    fi

    modprobe ec_sys write_support=1 2>/dev/null || true
    io=/sys/kernel/debug/ec/ec0/io
    if [ ! -r "$io" ]; then
      echo "msi-ec: fant ikke $io — kan ikke lese EC-firmware"
      exit 0
    fi

    ver=$(dd if="$io" bs=1 skip=160 count=12 status=none | tr -cd '[:alnum:].')
    case "$ver" in
      *.*) ;;
      *) echo "msi-ec: ulesbar EC-firmware ('$ver')"; exit 0 ;;
    esac

    cand=$(grep -m1 "^''${ver%.*}\." ${fwList} || true)
    if [ -z "$cand" ]; then
      echo "msi-ec: EC-firmware $ver ikke stoettet (ingen konfig for ''${ver%.*})"
      exit 0
    fi

    echo "msi-ec: EC-firmware $ver ukjent for driveren — bruker konfig $cand"
    modprobe msi-ec firmware="$cand" || echo "msi-ec: lasting feilet"
    exit 0
  '';
in
{
  # Build the msi-ec module for the running kernel, if available.
  boot.extraModulePackages = lib.mkAfter (lib.optional (msiEcPkg != null) msiEcPkg);

  # Only ec_sys here; msi-ec is loaded by msi-ec-autoload, since a firmware=
  # parameter may be needed and systemd-modules-load would otherwise fail.
  boot.kernelModules = lib.mkAfter [ "ec_sys" ];

  # Allow EC writes, for fan curves and similar.
  boot.extraModprobeConfig = lib.mkAfter ''
    options ec_sys write_support=1
  '';

  # Install mcontrolcenter if available.
  environment.systemPackages = lib.mkAfter (lib.optional (mccPkg != null) mccPkg);

  # Make the msi-ec sysfs nodes writable from userspace.
  services.udev.extraRules = ''
    ACTION=="add|change", SUBSYSTEM=="platform", KERNEL=="msi-ec", RUN+="/bin/sh -c 'chmod 0666 /sys/devices/platform/msi-ec/fan_mode /sys/devices/platform/msi-ec/shift_mode /sys/devices/platform/msi-ec/cooler_boost 2>/dev/null || true'"
  '';

  # Root helper for the statusbar Fans popup: EC fan-table writes (curve
  # control) go through its socket on /run/nixly-fand.sock, so ec_sys
  # write_support stays behind a validated interface.  Without it the
  # popup shows "Curve control needs nixly-fand · helper off".
  systemd.services.nixly-fand = {
    description = "nixlytile fan control helper";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-modules-load.service" "msi-ec-autoload.service" ];
    serviceConfig = {
      Type = "exec";
      ExecStart = "${pkgs.nixlytile}/bin/nixly-fand";
      Restart = "on-failure";
      RestartSec = 5;
    };
  };

  systemd.services.msi-ec-autoload = lib.mkIf (msiEcPkg != null) {
    description = "Load msi-ec with a matching EC firmware configuration";
    after = [ "systemd-modules-load.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = autoload;
    };
  };

  # No shift_mode or fan_mode here; picking a profile is userspace's job.
}
