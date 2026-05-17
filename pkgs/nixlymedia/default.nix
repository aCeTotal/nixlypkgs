{ lib
, rustPlatform
, fetchFromGitHub
, pkg-config
, cmake
, makeWrapper
, mpv-unwrapped
, openssl
, fontconfig
, freetype
, libxkbcommon
, wayland
, libGL
, libva
, libvdpau
, vulkan-loader
, alsa-lib
, udev
}:

let
  runtimeLibs = [
    mpv-unwrapped
    libGL
    libva
    libvdpau
    libxkbcommon
    wayland
    fontconfig
    freetype
    vulkan-loader
    alsa-lib
    udev
  ];
in
rustPlatform.buildRustPackage rec {
  pname = "nixlymedia";
  version = "0-unstable-2026-05-17";

  src = fetchFromGitHub {
    owner = "aCeTotal";
    repo = "nixlymedia";
    rev = "1fb917f1b2c4340fca0c99f9d357588a89868ccd";
    hash = "sha256-bojxRdQGP2kvABnBax0ReMzBKXrscCHCtFbov/G2E8g=";
  };

  cargoLock = {
    lockFile = "${src}/Cargo.lock";
  };

  nativeBuildInputs = [
    pkg-config
    cmake
    makeWrapper
  ];

  buildInputs = [
    mpv-unwrapped
    openssl
    fontconfig
    freetype
    libxkbcommon
    wayland
    libGL
    udev
  ];

  postFixup = ''
    patchelf \
      --set-rpath "${lib.makeLibraryPath runtimeLibs}" \
      $out/bin/nixlymedia
  '';

  meta = with lib; {
    description = "Nixly Media desktop client (egui + libmpv) for nixlymediaserver";
    homepage = "https://github.com/aCeTotal/nixlymedia";
    license = licenses.gpl3Plus;
    platforms = platforms.linux;
    mainProgram = "nixlymedia";
  };
}
