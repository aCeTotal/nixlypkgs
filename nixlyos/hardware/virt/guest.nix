{ ... }:

# Shared failsafe for every hypervisor guest. Rendering must always come up:
# hardware.graphics gives virtio-gpu/virgl a real driver and llvmpipe the
# swrast fallback, and software cursor avoids the classic invisible-cursor
# bug on paravirt display stacks.
{
  hardware.graphics.enable = true;

  environment.sessionVariables = {
    WLR_NO_HARDWARE_CURSORS = "1";
  };
}
