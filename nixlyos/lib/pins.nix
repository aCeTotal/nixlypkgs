# Pin packages to cached store paths.
pinsFiles:

{ lib, ... }:

let
  # Later files win.
  pins = builtins.foldl' (merged: file: merged // (if builtins.pathExists file then import file else { })) { } pinsFiles;

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
    (final: prev: builtins.mapAttrs (pin prev) (lib.filterAttrs (name: _: prev ? ${name}) pins))
  ];
}
