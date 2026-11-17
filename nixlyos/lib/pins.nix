# Failed packages keep last build.
pinsFile:

{ lib, ... }:

let
  pins = if builtins.pathExists pinsFile then import pinsFile else { };

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
  # After overlays.default's re-application.
  nixpkgs.overlays = lib.mkAfter [
    (final: prev: builtins.mapAttrs (pin prev) pins)
  ];
}
