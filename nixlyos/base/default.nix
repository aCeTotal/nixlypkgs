# Everything that runs NixlyOS, in the same activation order as always.
# hardware/ (cpu, gpu, machine profile) is appended by lib.mkNixlySystem from
# the scanner data in ~/.local/nixlyos; services/ holds detect-activated
# extras; apps/ holds programs that ship preconfigured.
{ lib, hwData, ... }:

let
  # x86-only stacks: Steam/Proton/Wine (gaming), the proton-path-baking
  # prewarm, and the Citrix binary bundle have no aarch64 builds, and even
  # referencing them fails the eval on an ARM SBC.
  isX86 = hwData.platform.arch == "x86_64";
in
{
  imports = [
    ./mode.nix
    ./mode-switch.nix
    ./input.nix
    ./distro.nix
    ./boot.nix
    ./SDDM.nix
    ./networking.nix
    ./shape.nix
    ./speedtest.nix
    ./nic-latency.nix
    ./dns-ecs.nix
    ./tailscale.nix
    ./nix.nix
    ./lockscreen.nix
    ./nfs.nix
    ./nfs-readahead.nix
    ./ssh.nix
  ]
  ++ lib.optional isX86 ../apps/gaming.nix
  ++ [
    ../apps/gametune.nix
    ./packages.nix
    ../apps/totalvim.nix
    ./users.nix
    ./timezone_locale.nix
    ./system_services.nix
    ./docs.nix
    ./perf.nix
  ]
  ++ lib.optional isX86 ./prewarm.nix
  ++ [
    ./overhead.nix
    ./wayland.nix
    ./sound.nix
    ./mic.nix
    ./bluetooth.nix
    ./btpair
    ./zram.nix
    ./hibernate.nix
    ./security.nix
    ./sandbox.nix
    ./attack-surface.nix
    ./secureboot.nix
    ./snapshots.nix
    ./audit.nix
    ./scanbox
    ./usb
    ./downloads
    ./keyring.nix
    ./power.nix
    ./diskd.nix
    ./disks-auto.nix
    ./nixlyos-tools.nix
    ./update-stage.nix
    ./nixlytile.nix
    ../apps/newsboat.nix
    ../apps/w3m.nix
    ../apps/viewers.nix
    ../apps/mpv.nix
    ../apps/retroarch.nix
    ../services/drawingtablet.nix
  ]
  ++ lib.optional isX86 ../apps/citrix.nix
  ++ [
    ../apps/dcspit.nix
    ../htpc
    ./capture.nix
    ./idle.nix
    ../hardware/profile.nix
    ../services/on-demand
  ];
}
