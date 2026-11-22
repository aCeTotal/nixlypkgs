# Module registry the panel reads.
{ lib }:

let
  hardwareDir = ../hardware;
  kinds = lib.filterAttrs (_: type: type == "directory") (builtins.readDir hardwareDir);
  modulesOf = kind: lib.filterAttrs (file: type: type == "regular" && lib.hasSuffix ".nix" file)
    (builtins.readDir (hardwareDir + "/${kind}"));

  # Display order of categories.
  categories = [
    { name = "system"; title = "System"; }
    { name = "boot"; title = "Oppstart og sikkerhet"; }
    { name = "network"; title = "Nettverk"; }
    { name = "session"; title = "Skrivebord og lyd"; }
    { name = "apps"; title = "Programmer"; }
    { name = "gaming"; title = "Spill"; }
    { name = "htpc"; title = "HTPC"; }
    { name = "services"; title = "Tjenester"; }
    { name = "home"; title = "Brukeroppsett"; }
    { name = "hardware"; title = "Maskinvare"; }
  ];

  selectable = map
    (module: {
      inherit (module) name title category profiles;
      path = "nixlyos/${module.file}";
      x86 = module.x86 or false;
      required = module.required or false;
      automatic = false;
    })
    (import ../catalog.nix);

  # Chosen per machine by nixlyos-detect-hw.
  automatic = lib.concatLists (lib.mapAttrsToList
    (kind: _: lib.mapAttrsToList
      (file: _:
        let name = lib.removeSuffix ".nix" file; in
        {
          name = "${kind}/${name}";
          title = "${kind}: ${name}";
          category = "hardware";
          profiles = [ ];
          path = "nixlyos/hardware/${kind}/${file}";
          x86 = false;
          required = false;
          automatic = true;
        })
      (modulesOf kind))
    kinds);
in
{
  inherit categories;
  modules = selectable ++ automatic;
}
