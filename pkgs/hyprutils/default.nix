{
  lib,
  stdenv,
  cmake,
  fetchFromGitHub,
  pixman,
  pkg-config,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "hyprutils";
  version = "0.8.0";

  src = fetchFromGitHub {
    owner = "hyprwm";
    repo = "hyprutils";
    rev = "v0.8.0";
    hash = "sha256-ZPN5ycmSRSzLUUo/4JYyrbcUQn71E86+sNE1+5qJD7Q=";
  };

  nativeBuildInputs = [
    cmake
    pkg-config
  ];

  buildInputs = [
    pixman
  ];

  cmakeBuildType = "Release";
  strictDeps = true;

  meta = {
    description = "Utility library for the Hypr* ecosystem";
    homepage = "https://github.com/hyprwm/hyprutils";
    license = lib.licenses.bsd3;
    platforms = lib.platforms.linux ++ lib.platforms.freebsd;
  };
})
