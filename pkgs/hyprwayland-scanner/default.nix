{
  lib,
  stdenv,
  cmake,
  fetchFromGitHub,
  pkg-config,
  wayland-scanner,
  wayland-protocols,
  pugixml,
}:

stdenv.mkDerivation {
  pname = "hyprwayland-scanner";
  version = "0.4.5";

  src = fetchFromGitHub {
    owner = "aCeTotal";
    repo = "hyprwayland-scanner";
    rev = "f6cf414ca0e16a4d30198fd670ec86df3c89f671";
    hash = "sha256-Uan1Nl9i4TF/kyFoHnTq1bd/rsWh4GAK/9/jDqLbY5A=";
  };

  nativeBuildInputs = [
    cmake
    pkg-config
  ];

  buildInputs = [
    pugixml
    wayland-protocols
    wayland-scanner
  ];

  cmakeBuildType = "Release";
  strictDeps = true;

  meta = {
    description = "Wayland scanner used by Hyprland and its ecosystem";
    homepage = "https://github.com/aCeTotal/hyprwayland-scanner";
    license = lib.licenses.bsd3;
    platforms = lib.platforms.linux ++ lib.platforms.freebsd;
  };
}
