inputs: final: prev:
let
  callPackage = final.callPackage;
in {
  winboat = callPackage ../pkgs/winboat { };
  winintegration = callPackage ../pkgs/winintegration { };
  winstripping = callPackage ../pkgs/winstripping { };
  speedtree = callPackage ../pkgs/speedtree { };
  nixlytile = callPackage ../pkgs/nixlytile { libepoxy = final.libepoxy-nixly; };
  claude = callPackage ../pkgs/claude { };
  nixlymediaserver = callPackage ../pkgs/nixlymediaserver { };
  citrix-workspace-nixly = callPackage ../pkgs/citrix-workspace-nixly { };
  nixly_steam = callPackage ../pkgs/nixly_steam { };
  libepoxy-nixly = callPackage ../pkgs/libepoxy { };
  xwayland = callPackage ../pkgs/xwayland { libepoxy = final.libepoxy-nixly; };
}
