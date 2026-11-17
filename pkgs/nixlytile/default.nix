{ lib
, stdenv
, fetchFromGitHub
, fetchurl
, linkFarm
, pkg-config
, makeWrapper
, autoPatchelfHook
, addDriverRunpath
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
, libgbm
, hwdata
, libdisplay-info
, libxcb-errors
, cairo
, librsvg
, gdk-pixbuf
, qrencode
, quirc
, hicolor-icon-theme
, adwaita-icon-theme
, papirus-icon-theme
, libpng
, libjpeg
, ffmpeg
, pipewire
, libass
, libva
, vulkan-loader
, vulkan-headers
, glslang
, swaybg
, brightnessctl
, xdg-utils
, thunar
, thunar-volman
, thunar-archive-plugin
, networkmanager
, networkmanagerapplet
, wireplumber
, pavucontrol
, blueman
, fd
, findutils
, coreutils
, gnused
, gnugrep
, alacritty
, foot
, libnotify
, wtype
, grim
, slurp
, wl-clipboard
, matugen
, nerd-fonts
, nixlycc
}:

let
  nixlytileSrc = fetchFromGitHub {
    owner = "aCeTotal";
    repo = "nixlytile";
    rev = "3ed6cb32fe12c171d03c4b7682b93530f97a6f4c";
    hash = "sha256-3s4VqSVDftueJj1pLDj7hgCqchsb7a1J3vxwPrJiOgI=";
  };

  gazeModel = name: hash: fetchurl {
    url = "https://github.com/google/mediapipe/raw/v0.8.9/mediapipe/modules/${name}";
    inherit hash;
  };

  gazeModels = linkFarm "nixlytile-gaze-models" [
    {
      name = "face_detection_short_range.tflite";
      path = gazeModel "face_detection/face_detection_short_range.tflite"
        "sha256-O8GC658zkl2eWLXI1ZMIp2D0reqPKCNw5CjFEhLCZjM=";
    }
    {
      name = "face_landmark.tflite";
      path = gazeModel "face_landmark/face_landmark.tflite"
        "sha256-xgP6YUkhmj6Uh9yavXoMJEdMdyYyc9JIaDeM30CqJtE=";
    }
    {
      name = "iris_landmark.tflite";
      path = gazeModel "iris_landmark/iris_landmark.tflite"
        "sha256-0XRNKgnCX1AdOeuk+v9H5T7MqIUsXOGbzo7qw5NXUh8=";
    }
  ];

  runtimeDeps = [
    matugen
    swaybg
    brightnessctl
    xdg-utils
    xwayland

    thunar
    thunar-volman
    thunar-archive-plugin

    networkmanager
    networkmanagerapplet

    pipewire
    wireplumber
    pavucontrol

    blueman

    fd
    findutils
    coreutils
    gnused
    gnugrep

    alacritty
    foot

    libnotify

    wtype

    grim
    slurp
    wl-clipboard

    nixlycc
  ];
in

stdenv.mkDerivation {
  pname = "nixlytile";
  version = "2026.11.17";

  passthru.providedSessions = [ "nixlytile" ];

  src = nixlytileSrc;

  nativeBuildInputs = [
    pkg-config
    wayland
    wayland-scanner
    wayland-protocols
    glslang
    makeWrapper
    autoPatchelfHook
    addDriverRunpath
  ];

  buildInputs = [
    wayland
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
    libxcb-errors
    seatd
    libgbm
    libdisplay-info
    hwdata

    cairo
    librsvg
    gdk-pixbuf
    qrencode
    quirc
    hicolor-icon-theme
    adwaita-icon-theme
    papirus-icon-theme
    libpng
    libjpeg
    ffmpeg
    pipewire
    libass
    libva
    vulkan-loader
    vulkan-headers
  ];

  makeFlags = [
    "PKG_CONFIG=${pkg-config}/bin/pkg-config"
    "ICON_FONT_DIR=${nerd-fonts.symbols-only}/share/fonts"
    "GAZE_MODEL_DIR=${gazeModels}"
  ];

  dontWrapQtApps = true;

  enableParallelBuilding = true;

  installPhase = ''
    runHook preInstall

    make PREFIX=$out \
         MANDIR=$out/share/man \
         DATADIR=$out/share \
         install

    wrapProgram $out/bin/nixlytile \
      --set NIXLY_RENDERER vulkan \
      --prefix PATH : ${lib.makeBinPath runtimeDeps} \
      --prefix XDG_DATA_DIRS : "${nixlycc}/share" \
      --run 'l="''${XDG_STATE_HOME:-$HOME/.local/state}/nixlytile"; mkdir -p "$l" && { [ -s "$l/session.log" ] && mv -f "$l/session.log" "$l/session.log.1"; exec 2>>"$l/session.log"; echo "=== session start $(date -Is) ===" >&2; }'

    runHook postInstall
  '';

  postFixup = ''
    addDriverRunpath $out/bin/nixlytile
  '';

  meta = with lib; {
    description = "Nixlytile - a tiling Wayland compositor for NixlyOS";
    homepage = "https://github.com/aCeTotal/nixlytile";
    license = licenses.gpl3Plus;
    platforms = platforms.linux;
    mainProgram = "nixlytile";
  };
}
