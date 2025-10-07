final: prev:
let
  callPackage = prev.callPackage;
in {
  nixly-hello = callPackage ../pkgs/nixly-hello { };
  winboat = callPackage ../pkgs/winboat { };
  winintegration = callPackage ../pkgs/winintegration { };
  winstripping = callPackage ../pkgs/winstripping { };
}
