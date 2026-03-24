inputs: final: prev:
let
  callPackage = final.callPackage;
in {
  speedtree = callPackage ../pkgs/speedtree { };
  nixlytile = callPackage ../pkgs/nixlytile { libepoxy = final.libepoxy-nixly; };
  claude = callPackage ../pkgs/claude { };
  nixlymediaserver = callPackage ../pkgs/nixlymediaserver { };
  citrix-workspace-nixly = callPackage ../pkgs/citrix-workspace-nixly { };
  nixly_steam = callPackage ../pkgs/nixly_steam { };
  libepoxy-nixly = callPackage ../pkgs/libepoxy { };
  blender = callPackage ../pkgs/blender/ { };
}
