inputs: final: prev:
let
  callPackage = final.callPackage;
in {
  nixly-hello = callPackage ../pkgs/nixly-hello { };
  nixly_renderer = callPackage ../pkgs/nixly_renderer {
    aquamarineSrc = inputs."aquamarine-src";
  };
  nixly = callPackage ../pkgs/nixly {
    hyprlandSrc = inputs."hyprland-src";
    aquamarine = final.nixly_renderer;
  };
  winboat = callPackage ../pkgs/winboat { };
  winintegration = callPackage ../pkgs/winintegration { };
  winstripping = callPackage ../pkgs/winstripping { };
}
