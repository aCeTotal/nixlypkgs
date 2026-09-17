{ lib, hwData, ... }:

let
  isArm = hwData.platform.arch == "aarch64";
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
}
