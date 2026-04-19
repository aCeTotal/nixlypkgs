{ lib
, stdenv
, fetchFromGitHub
, pkg-config
, makeWrapper
, autoPatchelfHook
, addDriverRunpath
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
}:

let
  nixlytileSrc = fetchFromGitHub {
    owner = "aCeTotal";
    repo = "nixlytile";
    rev = "70fee0a38d1291fbad2f7b64e7def23315ce6e5f";
    hash = "sha256-gcg3ckpKytALU2Q+ModvR4TNJsuNTxhvDwr9muMchi4=";
  };

  wlrootsLocal = stdenv.mkDerivation {
    pname = "wlroots-nixly";
    version = "";
    src = nixlytileSrc + "/wlroots";
    patches = [
    ];
    nativeBuildInputs = [ meson ninja pkg-config wayland-scanner glslang ];
    buildInputs = [
      wayland wayland-protocols libdrm libxkbcommon pixman libinput
      xwayland seatd libxcb libxcb-wm
      libgbm hwdata libliftoff libdisplay-info lcms2 libxcb-errors
      vulkan-loader vulkan-headers
    ];
    mesonFlags = [
      "-Dexamples=false"
      "-Dxwayland=enabled"
      "-Dbackends=drm,libinput"
      "-Drenderers=vulkan"
      "-Dallocators=gbm"
    ];
  };

  wlrootsPc = "wlroots-0.20";

  runtimeDeps = [
    # Core utilities
    swaybg
    brightnessctl
    xdg-utils
    xwayland

    # File manager
    thunar
    thunar-volman
    thunar-archive-plugin

    # Network management
    networkmanager
    networkmanagerapplet

    # Audio
    pipewire
    wireplumber
    pavucontrol

    # Bluetooth
    blueman

    # System utilities
    fd
    findutils
    coreutils
    gnused
    gnugrep

    # Terminal
    alacritty
    foot

    # Notifications
    libnotify

    # Virtual keyboard input
    wtype

    # Screenshot
    grim
    slurp
    wl-clipboard
  ];
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
    addDriverRunpath
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
    vulkan-loader
    vulkan-headers
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
      --set WLR_RENDERER vulkan \
      --prefix PATH : ${lib.makeBinPath runtimeDeps} \
      --prefix XDG_DATA_DIRS : "${papirus-icon-theme}/share:${adwaita-icon-theme}/share:${hicolor-icon-theme}/share:${shared-mime-info}/share"

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
