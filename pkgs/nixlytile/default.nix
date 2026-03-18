{ lib
, stdenv
, fetchFromGitHub
, pkg-config
, makeWrapper
, autoPatchelfHook
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
, mesa
, libGL
, vulkan-loader
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
    rev = "35f383a7d1bcfa79581912260beffa65aa9794e0";
    hash = "sha256-2NHS+YTbGx3dx+gLNdA8By1Sxq6cZbmZttk+sLsQlco=";
  };

  nativeBuildInputs = [
    pkg-config
    wayland
    wayland-scanner
    wayland-protocols
    makeWrapper
    autoPatchelfHook
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
    mesa
    libGL
    vulkan-loader
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
      --prefix PATH : ${lib.makeBinPath [ swaybg brightnessctl xwayland ]} \
      --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath [ mesa mesa.drivers libGL vulkan-loader ]}" \
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
