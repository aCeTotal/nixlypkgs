# System mode: "desktop" (default) or "htpc" (couch box: auto-login,
# Steam Big Picture session, nightly auto-update, htpc/ modules active).
#
# Set per machine in the LOCAL file ~/.local/nixlyos/local.nix:
#
#   { ... }: { nixlyos.mode = "htpc"; }
#
# A machine that never sets it stays a desktop, exactly as today.
{ lib, config, ... }:

let
  opts = import ./options.nix;
in
{
  options.nixlyos.mode = lib.mkOption {
    type = lib.types.enum [ "desktop" "htpc" ];
    # Back-compat: the old in-repo options.nix systemMode (2 = htpc) still
    # works as the default when local.nix does not set nixlyos.mode.
    default = if (opts.systemMode or 1) == 2 then "htpc" else "desktop";
    description = "NixlyOS machine role; local.nix overrides per machine.";
  };

  # Active-mode marker: install_htpc/install_desktop verify a switch took
  # effect by reading this file.
  config.environment.etc."nixlyos-mode".text = config.nixlyos.mode;
}
