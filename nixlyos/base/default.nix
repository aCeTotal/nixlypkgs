# Everything that runs NixlyOS, in the same activation order as always.
# hardware/ (cpu, gpu, machine profile) is appended by lib.mkNixlySystem from
# the scanner data in ~/.local/nixlyos; services/ holds detect-activated
# extras; apps/ holds programs that ship preconfigured.
{ ... }:

{
  imports = [
    ./mode.nix
    ./mode-switch.nix
    ./input.nix
    ./distro.nix
    ./boot.nix
    ./SDDM.nix
    ./networking.nix
    ./tailscale.nix
    ./ssh_gate.nix
    ./nix.nix
    # ./lockscreen.nix  # disabled: no auto-lock/lockscreen
    ./nfs.nix
    ./ssh.nix
    ../apps/gaming.nix
    ../apps/gametune.nix
    ./packages.nix
    ../apps/totalvim.nix
    ./users.nix
    ./timezone_locale.nix
    ./system_services.nix
    ./docs.nix
    ./perf.nix
    ./prewarm.nix
    ./overhead.nix
    ./wayland.nix
    ./sound.nix
    ./bluetooth.nix
    ./zram.nix
    ./hibernate.nix
    ./security.nix
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
    ../apps/citrix.nix
    ../apps/dcspit.nix
    ../htpc
    ./capture.nix
    ./idle.nix
    ../hardware/profile.nix
    ../services/on-demand
  ];
}
