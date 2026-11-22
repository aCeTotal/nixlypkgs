# Catalog modules a machine imports.
{ hwData, nixlySelection }:

let
  catalog = import ../catalog.nix;
  # No aarch64 builds of these.
  fits = module: hwData.platform.arch == "x86_64" || !(module.x86 or false);
  # Pre-panel machines keep today's set.
  wanted = module: (module.required or false)
    || (if nixlySelection == null then module.profiles != [ ] else builtins.elem module.name nixlySelection);
in
{
  # "home" picks home-manager modules.
  pick = side: map (module: ../. + "/${module.file}")
    (builtins.filter (module: (module.category == "home") == (side == "home") && fits module && wanted module) catalog);
}
