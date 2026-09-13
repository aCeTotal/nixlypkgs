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
  version = "2026.09.13";

  src = fetchFromGitHub {
    name = "nixlymedia-src-34d8a55";
    owner = "aCeTotal";
    repo = "nixlymedia";
    rev = "34d8a55990e07a538830bea941c634eb25cdf7bc";
    hash = "sha256-m1R3tj/YRxww1DGyP08mj3dcvAmUZYTeywZ0FbSFceE=";
  };

  cargoHash = "sha256-1ao6Nd/yc8Z6aaqCtrTlyZYwmGRLey5vEuP+hQJlt2s=";

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
    wrapProgram $out/bin/nixlymedia \
      --set NIXLY_LOG 1 \
      --set NIXLY_LOG_FILE /tmp/nixlymedia.log
  '';

  meta = with lib; {
    description = "Nixly Media desktop client (egui + libmpv) for nixlymediaserver";
    homepage = "https://github.com/aCeTotal/nixlymedia";
    license = licenses.gpl3Plus;
    platforms = platforms.linux;
    mainProgram = "nixlymedia";
  };
}
