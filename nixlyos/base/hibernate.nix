{ config, lib, hwData, ... }:

let
  hw = hwData.resources;
  nvidia = builtins.elem "nvidia" config.services.xserver.videoDrivers;
in
{
  # Lid close on battery = suspend-then-hibernate (idle.nix): S3 for the
  # first 2 h (instant wake), then an RTC alarm wakes the machine just long
  # enough to write the hibernation image and power off (0 W). If the
  # hibernate step ever fails, systemd drops back into suspend — never a
  # lost session.
  #
  # Machine-independent by design: NixOS creates the swapfile at activation
  # (btrfs gets `btrfs filesystem mkswapfile`, others dd + chattr +C), and
  # systemd picks the swap device and computes the file's physical offset
  # itself at hibernate time, recording it in the HibernateLocation EFI
  # variable that the systemd initrd reads on the next boot. No per-machine
  # UUID or resume_offset anywhere; needs only EFI (systemd-boot implies it)
  # and boot.initrd.systemd (on in boot.nix).

  # /swapfile, not /swap/swapfile: the btrfs creation path does not mkdir
  # the parent, and / always exists. Full RAM + headroom so even an
  # uncompressible image fits. zram (prio 100) takes all runtime swap;
  # this file only ever holds the hibernation image.
  swapDevices = [{
    device = "/swapfile";
    size = (hw.memGiB + 5) * 1024;
    priority = 0;
  }];

  systemd.sleep.settings.Sleep.HibernateDelaySec = "2h";

  # The NixOS nvidia module only hooks nvidia-suspend/-resume into
  # systemd-suspend.service and systemd-hibernate.service; the
  # suspend-then-hibernate unit is separate and would skip the dGPU
  # state save/restore without these. AMD/Intel need nothing here.
  systemd.services.nvidia-suspend = lib.mkIf nvidia {
    before = [ "systemd-suspend-then-hibernate.service" ];
    wantedBy = [ "systemd-suspend-then-hibernate.service" ];
  };
  systemd.services.nvidia-resume = lib.mkIf nvidia {
    after = [ "systemd-suspend-then-hibernate.service" ];
    wantedBy = [ "systemd-suspend-then-hibernate.service" ];
  };
}
