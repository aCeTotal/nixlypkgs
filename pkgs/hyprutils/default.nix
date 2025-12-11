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
  version = "0.11.0";

  src = fetchFromGitHub {
    owner = "aCeTotal";
    repo = "hyprutils";
    rev = "fe686486ac867a1a24f99c753bb40ffed338e4b0";
    hash = "sha256-rGbEMhTTyTzw4iyz45lch5kXseqnqcEpmrHdy+zHsfo=";
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
    homepage = "https://github.com/aCeTotal/hyprutils";
    license = lib.licenses.bsd3;
    platforms = lib.platforms.linux ++ lib.platforms.freebsd;
  };
})
