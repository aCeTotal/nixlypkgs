# Pin packages to the panel's cached store paths.
pinsFile:

{ lib, ... }:

let
  pins = import pinsFile;

  pin = prev: name: path:
    let
      pkg = prev.${name} // {
        outPath = builtins.appendContext path { ${path}.path = true; };
        outputs = [ "out" ];
        meta = (prev.${name}.meta or { }) // { outputsToInstall = [ "out" ]; };
      };
    in
    pkg // { out = pkg; };
in
{
  # Last, so pins win.
  nixpkgs.overlays = lib.mkAfter [
    (final: prev: builtins.mapAttrs (pin prev) (lib.filterAttrs (name: _: prev ? ${name}) pins))
  ];
}
