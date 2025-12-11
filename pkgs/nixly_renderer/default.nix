{
  lib,
  stdenv,
  cmake,
  fetchFromGitHub,
  aquamarineSrc ? null,
  hwdata,
  hyprutils,
  hyprwayland-scanner,
  libdisplay-info,
  libdrm,
  libffi,
  libGL,
  libinput,
  libgbm,
  nix-update-script,
  pixman,
  pkg-config,
  seatd,
  udev,
  wayland,
  wayland-protocols,
  wayland-scanner,
}:
stdenv.mkDerivation (finalAttrs: {
  pname = "nixly_renderer";
  version = "git";

  src = aquamarineSrc or fetchFromGitHub {
    owner = "hyprwm";
    repo = "aquamarine";
    rev = "v0.9.5";
    hash = "sha256-UNzYHLWfkSzLHDep5Ckb5tXc0fdxwPIrT+MY4kpQttM=";
  };

  nativeBuildInputs = [
    cmake
    hyprwayland-scanner
    pkg-config
  ];

  buildInputs = [
    hwdata
    hyprutils
    libdisplay-info
    libdrm
    libffi
    libGL
    libinput
    libgbm
    pixman
    seatd
    udev
    wayland
    wayland-protocols
    wayland-scanner
  ];

  strictDeps = true;

  outputs = [
    "out"
    "dev"
  ];

  cmakeBuildType = "RelWithDebInfo";

  passthru.updateScript = nix-update-script { };

  meta = {
    description = "NixlyOS renderer (aquamarine fork)";
    homepage = "https://github.com/aCeTotal/aquamarine";
    license = lib.licenses.bsd3; # upstream license retained
    platforms = lib.platforms.linux ++ lib.platforms.freebsd;
  };
})
