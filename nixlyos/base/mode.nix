# System mode: "desktop" (default) or "htpc" (couch box: auto-login,
# one-app-at-a-time session, nightly auto-update, htpc/ modules active).
#
# Set per machine in the LOCAL file ~/.local/nixlyos/local.nix:
#
#   { ... }: { nixlyos.mode = "htpc"; }
#
# A machine that never sets it stays a desktop, exactly as today.
{ lib, config, hwData, ... }:

let
  opts = import ./options.nix;
in
{
  # HTPC mode is Steam/GeForce NOW-based and x86-only; failing the eval with
  # a clear message beats an unbuildable closure on an ARM SBC.
  config.assertions = [{
    assertion = !(config.nixlyos.mode == "htpc" && hwData.platform.arch == "aarch64");
    message = "nixlyos.mode = \"htpc\" er x86-only (Steam/GFN); denne ARM-maskinen må bruke \"desktop\".";
  }];

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
