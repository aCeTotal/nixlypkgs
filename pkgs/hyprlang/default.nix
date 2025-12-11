{
  lib,
  stdenv,
  fetchFromGitHub,
  cmake,
  pkg-config,
  hyprutils,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "hyprlang";
  version = "0.6.7";

  src = fetchFromGitHub {
    owner = "aCeTotal";
    repo = "hyprlang";
    rev = "0d00dc118981531aa731150b6ea551ef037acddd";
    hash = "sha256-54ltTSbI6W+qYGMchAgCR6QnC1kOdKXN6X6pJhOWxFg=";
  };

  nativeBuildInputs = [
    cmake
    pkg-config
  ];

  buildInputs = [
    hyprutils
  ];

  outputs = [
    "out"
    "dev"
  ];

  doCheck = true;

  meta = {
    homepage = "https://github.com/aCeTotal/hyprlang";
    description = "Official implementation library for the hypr config language";
    license = lib.licenses.lgpl3Only;
    platforms = lib.platforms.all;
    teams = [ lib.teams.hyprland ];
  };
})
