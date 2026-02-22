{ lib
, stdenv
, fetchFromGitHub
, pkg-config
, makeWrapper
, wayland
, wayland-scanner
, wayland-protocols
, wlroots
, libinput
, libxkbcommon
, fcft
, tllist
, pixman
, libdrm
, systemd
, xwayland
, seatd
, xorg
, cairo
, librsvg
, gdk-pixbuf
, hicolor-icon-theme
, adwaita-icon-theme
, papirus-icon-theme
, libpng
, libjpeg
, ffmpeg
, pipewire
, libass
, libva
, swaybg
, brightnessctl
}:

let
  wlrootsPc = "wlroots-${lib.versions.majorMinor wlroots.version}";
in

stdenv.mkDerivation rec {
  pname = "nixlytile";
  version = "git";

  passthru.providedSessions = [ "nixlytile" ];

  src = fetchFromGitHub {
    owner = "aCeTotal";
    repo = "nixlytile";
    rev = "2a1d0f054bd15b76a4db7935ecf577bf21d44d71";
    hash = "sha256-5UTegHbNA7YX30BmQBXCeH2NLmqGoUflwJ74snN2hes=";
  };

  nativeBuildInputs = [
    pkg-config
    wayland
    wayland-scanner
    wayland-protocols
    makeWrapper
  ];

  buildInputs = [
    wayland
    wlroots
    libinput
    libxkbcommon
    fcft
    tllist
    pixman
    libdrm
    systemd
    xwayland
    xorg.libxcb
    xorg.xcbutilwm
    seatd

    cairo
    librsvg
    gdk-pixbuf
    hicolor-icon-theme
    adwaita-icon-theme
    papirus-icon-theme
    libpng
    libjpeg
    ffmpeg
    pipewire
    libass
    libva
  ];

  makeFlags = [
    "PKG_CONFIG=${pkg-config}/bin/pkg-config"
  ];

  dontWrapQtApps = true;

  buildPhase = ''
    runHook preBuild
    make \
      WLR_INCS="$(${pkg-config}/bin/pkg-config --cflags ${wlrootsPc})" \
      WLR_LIBS="$(${pkg-config}/bin/pkg-config --libs ${wlrootsPc})"
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    make PREFIX=$out \
         MANDIR=$out/share/man \
         DATADIR=$out/share \
         install

    wrapProgram $out/bin/nixlytile \
      --prefix PATH : ${lib.makeBinPath [ swaybg brightnessctl ]} \
      --prefix XDG_DATA_DIRS : "${papirus-icon-theme}/share:${adwaita-icon-theme}/share:${hicolor-icon-theme}/share"

    runHook postInstall
  '';

  meta = with lib; {
    description = "Nixlytile - a tiling Wayland compositor for NixlyOS";
    homepage = "https://github.com/aCeTotal/nixlytile";
    license = licenses.gpl3Plus;
    platforms = platforms.linux;
    mainProgram = "nixlytile";
  };
}
