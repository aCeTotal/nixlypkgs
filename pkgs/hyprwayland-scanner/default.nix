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
  version = "0.4.2";

  src = fetchFromGitHub {
    owner = "hyprwm";
    repo = "hyprwayland-scanner";
    rev = "b68dab23fc922eae99306988133ee80a40b39ca5";
    hash = "sha256-HIPEXyRRVZoqD6U+lFS1B0tsIU7p83FaB9m7KT/x6mQ=";
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
    homepage = "https://github.com/hyprwm/hyprwayland-scanner";
    license = lib.licenses.bsd3;
    platforms = lib.platforms.linux ++ lib.platforms.freebsd;
  };
}
