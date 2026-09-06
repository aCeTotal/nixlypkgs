# Static loader for the per-machine hardware profile. The data comes from
# nixlyos-detect-hw via ~/.local/nixlyos/hardware/profile.nix (hwData.profile):
# nixos-hardware module names plus flags, never paths, so the generated file
# stays valid across nixlyos versions.
{ inputs, lib, hwData, ... }:

let
  hw = inputs.nixos-hardware.nixosModules;
  p = hwData.profile;

  model = lib.findFirst (n: builtins.hasAttr n hw) null p.candidates;
  generic' = builtins.filter (n: builtins.hasAttr n hw) p.generic;
  missing = builtins.filter (n: !(builtins.hasAttr n hw)) p.generic;
in
lib.warnIf (missing != [ ])
  "hw/profile.nix: ukjente nixos-hardware-moduler: ${toString missing}"
{
  imports =
    map (n: hw.${n}) generic'
    ++ lib.optional (model != null) hw.${model}
    ++ lib.optional p.msiEc ./msi-ec.nix;

  # common-pc-laptop enables TLP when power-profiles-daemon is off, and TLP
  # would then own the governor and override perf.nix, so it is kept off.
  services.tlp.enable = lib.mkIf p.isLaptop (lib.mkForce false);
}
