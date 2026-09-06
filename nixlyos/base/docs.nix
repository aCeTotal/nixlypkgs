{ ... }:

{
  # The NixOS manual would otherwise be rebuilt every time, for something read on
  # nixos.org anyway; man pages are kept.
  documentation.nixos.enable = false;
}
