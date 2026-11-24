# Configene verifiseres, og katalogens standarder stemmer.
{ pkgs, kernels }:
let
  inherit (pkgs) lib;
  inherit (import ./settings.nix { inherit lib; }) knobs;
  expected = entry: lib.concatLists (lib.mapAttrsToList (knob: value: knobs.${knob}.options.${value}.checks) entry.defaults);
  defaults = name: entry: variant: pkgs.runCommand "kernel-defaults-${name}-${variant}" { } ''
    ${lib.concatMapStrings (check: ''
      grep -q '^CONFIG_${check}' ${kernels.${variant}.configfile} || { echo "${variant} lacks CONFIG_${check}"; exit 1; }
    '') (expected entry)}
    touch $out
  '';
in
lib.mapAttrs' (name: kernel: lib.nameValuePair "kernel-config-${name}" kernel.configfile) kernels
// lib.concatMapAttrs
  (name: entry: lib.listToAttrs (map
    (variant: lib.nameValuePair "kernel-defaults-${name}-${variant}" (defaults name entry variant))
    (lib.unique [ entry.variant entry.fallback ])))
  (import ./catalogue.nix)
