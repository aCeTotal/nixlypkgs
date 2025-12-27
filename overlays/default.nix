final: prev:
let
  pkgsUnstable = final.pkgsUnstable;
in {
  winboat = final.callPackage ../pkgs/winboat { };
  winstripping = final.callPackage ../pkgs/winstripping { };
}


