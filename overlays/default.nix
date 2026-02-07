inputs: final: prev:
let
  callPackage = final.callPackage;
in {
  winboat = callPackage ../pkgs/winboat { };
  winintegration = callPackage ../pkgs/winintegration { };
  winstripping = callPackage ../pkgs/winstripping { };
  speedtree = callPackage ../pkgs/speedtree { };
  nixlytile = callPackage ../pkgs/nixlytile { };
  claude = callPackage ../pkgs/claude { };
}
