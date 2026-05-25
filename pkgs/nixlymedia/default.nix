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
  version = "0-unstable-2026-05-25";

  src = fetchFromGitHub {
    owner = "aCeTotal";
    repo = "nixlymedia";
    rev = "6a197371d75563e2c3e53d4dfae58737864bc693";
    hash = "sha256-zQ4rH4yeXPPhIL8f7epZDrB4b1ND290jSV64Hf+Yjx0=";
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

  postInstall = ''
    for size in 16x16 32x32 64x64 128x128; do
      install -Dm644 \
        ${mpv-unwrapped}/share/icons/hicolor/$size/apps/mpv.png \
        $out/share/icons/hicolor/$size/apps/nixlymedia.png
    done
    install -Dm644 \
      ${mpv-unwrapped}/share/icons/hicolor/scalable/apps/mpv.svg \
      $out/share/icons/hicolor/scalable/apps/nixlymedia.svg

    install -Dm644 /dev/stdin $out/share/applications/nixlymedia.desktop <<EOF
    [Desktop Entry]
    Type=Application
    Name=Nixly Media
    GenericName=Media Client
    Comment=Nixly Media desktop client for nixlymediaserver
    Exec=nixlymedia
    Icon=nixlymedia
    Terminal=false
    Categories=AudioVideo;Player;Video;
    StartupWMClass=nixlymedia
    EOF
  '';

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
