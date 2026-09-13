{ ... }:

# Parallels guest. hardware.parallels.enable builds the proprietary tools
# against the running kernel and breaks on kernel bumps; the shared guest
# failsafe alone gives a working display, so the tools stay off until a
# machine actually needs shared folders.
{
  imports = [ ./guest.nix ];
}
