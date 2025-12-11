inputs: final: prev:
let
  callPackage = final.callPackage;
in {
  # Override Hypr components to the nixly forks
  hyprlang = callPackage ../pkgs/hyprlang { };
  hyprcursor = callPackage ../pkgs/hyprcursor { };
  hyprgraphics = callPackage ../pkgs/hyprgraphics { };
  hyprland-protocols = callPackage ../pkgs/hyprland-protocols { };
  hyprutils = callPackage ../pkgs/hyprutils { };
  hyprwayland-scanner = callPackage ../pkgs/hyprwayland-scanner { };
  hyprwire = callPackage ../pkgs/hyprwire { };
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
