{ pkgs, ... }:

# Elgato 4K capture cards (Cam Link 4K, HD60 X, 4K X, 4K S — all UVC).
# Kernel side is done upstream: the BOS-descriptor quirk that keeps the 4K X
# on its 10 Gbps link (4K60) shipped in mainline 6.19 and the Cam Link
# pixel-format + stall-recovery fixes are years old — the CachyOS kernel has
# all of it. Remaining system side:
{
  # USB autosuspend mid-stream drops frames or wedges the card until replug.
  services.udev.extraRules = ''
    SUBSYSTEM=="usb", ATTR{idVendor}=="0fd9", TEST=="power/control", ATTR{power/control}="on"
  '';

  # v4l2-ctl for format/rate inspection when a card misbehaves.
  environment.systemPackages = [ pkgs.v4l-utils ];
}
