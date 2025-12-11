{
  lib,
  stdenv,
  fetchFromGitHub,
  cmake,
  ninja,
}:
stdenv.mkDerivation (finalAttrs: {
  pname = "hyprland-protocols";
  version = "0.7.0";

  src = fetchFromGitHub {
    owner = "aCeTotal";
    repo = "hyprland-protocols";
    rev = "3f3860b869014c00e8b9e0528c7b4ddc335c21ab";
    hash = "sha256-P9zdGXOzToJJgu5sVjv7oeOGPIIwrd9hAUAP3PsmBBs=";
  };

  nativeBuildInputs = [
    cmake
    ninja
  ];

  meta = {
    homepage = "https://github.com/aCeTotal/hyprland-protocols";
    description = "Wayland protocol extensions for Hyprland";
    license = lib.licenses.bsd3;
    teams = [ lib.teams.hyprland ];
    platforms = lib.platforms.linux;
  };
})
