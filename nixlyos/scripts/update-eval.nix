# Hot subtrees first, then toplevel.
config:

let
  inherit (builtins) attrValues concatMap parallel;
  each = xs: parallel xs null;
  drvs = map (p: p.drvPath or null);
  sources = files: map (f: f.source.drvPath or null) (attrValues files);
  homes = attrValues config.home-manager.users or { };
in
parallel ([
  (each (sources config.environment.etc))
  (each (map (u: u.unit.drvPath or null) (attrValues config.systemd.units)))
  (each (drvs config.environment.systemPackages))
  config.boot.kernelPackages.kernel.drvPath or null
  config.system.build.initialRamdisk.drvPath or null
  config.hardware.graphics.package.drvPath or null
] ++ concatMap (home: [
  (each (sources home.home.file))
  (each (drvs home.home.packages))
]) homes) config.system.build.toplevel.drvPath
