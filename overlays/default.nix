final: prev:
let
  callPackage = prev.callPackage;
in {
  nixly-hello = callPackage ../pkgs/nixly-hello { };
}

