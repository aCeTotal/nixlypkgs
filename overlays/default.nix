final: prev:
let
  pkgsUnstable = final.pkgsUnstable;
in
prev // {
  winboat = final.callPackage ../pkgs/winboat {};
  winstripping = final.callPackage ../pkgs/winstripping {};
}



