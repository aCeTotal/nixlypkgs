{ lib
, stdenv
, fetchFromGitHub
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
, nixlycc
}:

let
  nixlytileSrc = fetchFromGitHub {
    owner = "aCeTotal";
    repo = "nixlytile";
    rev = "ac5593d25259f119bc2edad3839d93400e0b856a";
    hash = "sha256-VVZxhjIzN1HscLuOjsczBhlNRkq+chhVxW0tZO2pb00=";
  };

  runtimeDeps = [
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
  version = "2026.11.14";

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
      --prefix XDG_DATA_DIRS : "${nixlycc}/share:${papirus-icon-theme}/share:${adwaita-icon-theme}/share:${hicolor-icon-theme}/share:${shared-mime-info}/share" \
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
