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
  # A/V drift corrected at 4 ms.
  mpv = mpv-unwrapped.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [ ./mpv-av-drift.patch ];
  });

  runtimeLibs = [
    mpv
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
  version = "2026.11.08";

  src = fetchFromGitHub {
    name = "nixlymedia-src-8c19e08";
    owner = "aCeTotal";
    repo = "nixlymedia";
    rev = "0b8f018598d57727b21da3665d4fe7302ae1135d";
    hash = "sha256-/xka/Pbyno54HqT+Q12xncle7loXBY9usB+bmfAHBaQ=";
  };

  cargoHash = "sha256-kFugkS8x1TOVTwJ4gC1cVj3g3/6uDcE3vwh/2iSAcMI=";

  nativeBuildInputs = [
    pkg-config
    cmake
    makeWrapper
  ];

  buildInputs = [
    mpv
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
        ${mpv}/share/icons/hicolor/$size/apps/mpv.png \
        $out/share/icons/hicolor/$size/apps/nixlymedia.png
    done
    install -Dm644 \
      ${mpv}/share/icons/hicolor/scalable/apps/mpv.svg \
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
