{ lib
, stdenv
, fetchFromGitHub
, pkg-config
, makeWrapper
, autoPatchelfHook
, meson
, ninja
, wayland
, wayland-scanner
, wayland-protocols
, libinput
, libxkbcommon
, fcft
, tllist
, pixman
, libdrm
, systemd
, xwayland
, seatd
, libxcb
, libxcb-wm
, libepoxy
, libglvnd
, libgbm
, hwdata
, libliftoff
, libdisplay-info
, lcms2
, libxcb-errors
, cairo
, librsvg
, gdk-pixbuf
, hicolor-icon-theme
, adwaita-icon-theme
, papirus-icon-theme
, shared-mime-info
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
  nixlytileSrc = fetchFromGitHub {
    owner = "aCeTotal";
    repo = "nixlytile";
    rev = "a39b9a3f45f27fd8c92783e3d37853d9b477f397";
    hash = "sha256-ZMwNX5OAP/CcGMdoCekZskSsR2AX7A69B7+fmN6d3VQ=";
  };

  wlrootsLocal = stdenv.mkDerivation {
    pname = "wlroots";
    version = "0.20.0-rc4";
    src = nixlytileSrc + "/wlroots";
    nativeBuildInputs = [ meson ninja pkg-config wayland-scanner ];
    buildInputs = [
      wayland wayland-protocols libdrm libxkbcommon pixman libinput
      xwayland seatd libepoxy libglvnd libxcb libxcb-wm
      libgbm hwdata libliftoff libdisplay-info lcms2 libxcb-errors
    ];
    mesonFlags = [
      "-Dexamples=false"
      "-Dxwayland=enabled"
      "-Dbackends=drm,libinput"
      "-Drenderers=gles2"
      "-Dallocators=gbm"
    ];
  };

  wlrootsPc = "wlroots-0.20";
in

stdenv.mkDerivation {
  pname = "nixlytile";
  version = "git";

  passthru.providedSessions = [ "nixlytile" ];

  src = nixlytileSrc;

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
    wlrootsLocal
    libinput
    libxkbcommon
    fcft
    tllist
    pixman
    libdrm
    systemd
    xwayland
    libxcb
    libxcb-wm
    libepoxy
    libglvnd

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
      --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath [ mesa libGL vulkan-loader ]}" \
      --prefix XDG_DATA_DIRS : "${papirus-icon-theme}/share:${adwaita-icon-theme}/share:${hicolor-icon-theme}/share:${shared-mime-info}/share"

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
