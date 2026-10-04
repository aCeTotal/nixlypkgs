{ pkgs, lib, hwData, ... }:

let
  isArm = hwData.platform.arch == "aarch64";

  # Last peer gone: boltd exits.
  boltIdle = pkgs.writeShellScript "bolt-idle" ''
    for d in /sys/bus/thunderbolt/devices/*-*; do
      case ''${d##*/} in *-0|*:*) continue ;; esac
      [ -e "$d" ] && exit 0
    done
    exec ${pkgs.systemd}/bin/systemctl stop --no-block bolt.service
  '';
in
{
  # Kernel code that nothing here uses but a hostile device can reach by
  # alias autoload: FireWire does unrestricted DMA, the obscure net stacks
  # are historic CVE farms, and the rare filesystem parsers are exactly what
  # a crafted USB image targets. Blacklisting blocks the alias path.
  boot.blacklistedKernelModules = [
    # DMA over the wire
    "firewire-core"
    "firewire-ohci"
    "firewire-sbp2"

    # Unused network protocols
    "dccp"
    "sctp"
    "rds"
    "tipc"
    "n-hdlc"
    "ax25"
    "netrom"
    "x25"
    "rose"
    "decnet"
    "econet"
    "af_802154"
    "ipx"
    "appletalk"
    "psnap"
    "p8023"
    "p8022"
    "atm"

    # Filesystem parsers no disk here is formatted with
    "cramfs"
    "freevxfs"
    "jffs2"
    "hfs"
    "hfsplus"
    "gfs2"
    "ksmbd"

    # Test driver with a CVE history, loadable by any local user
    "vivid"
  ] ++ lib.optionals (!isArm) [
    # Legacy DMA-capable parallel/serial bridges
    "parport_pc"
    "ppdev"
  ];

  # Thunderbolt device authorization. The firmware security level decides
  # what this can enforce: set BIOS Thunderbolt to "User Authorization",
  # since "none" gives any plugged-in device PCIe/DMA access before boltd
  # ever sees it.
  services.hardware.bolt.enable = true;

  # Only a plugged-in peer wakes boltd.
  services.udev.extraRules = ''
    SUBSYSTEM=="thunderbolt", ENV{DEVTYPE}!="thunderbolt_device", ENV{SYSTEMD_WANTS}=""
    SUBSYSTEM=="thunderbolt", KERNEL=="*-0", ENV{SYSTEMD_WANTS}=""
    ACTION=="remove", SUBSYSTEM=="thunderbolt", ENV{DEVTYPE}=="thunderbolt_device", RUN+="${boltIdle}"
  '';
}
