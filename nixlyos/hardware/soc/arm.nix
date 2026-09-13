{ ... }:

# Generic ARM SoC graphics. Every supported SBC GPU (vc4/v3d on Raspberry Pi,
# panfrost/lima on Mali boards) is a mainline Mesa driver, so one module
# covers them all; board specifics (kernel, device tree, firmware) come from
# the matched nixos-hardware candidate module, with boot.nix as the failsafe.
# No enable32Bit: pkgsi686Linux does not exist on aarch64.
{
  hardware.graphics.enable = true;
  hardware.enableRedistributableFirmware = true;
}
