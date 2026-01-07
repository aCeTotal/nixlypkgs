{ lib
, stdenv
, fetchgit
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
, swaybg
, brightnessctl
}:

let
  wlrootsPc = "wlroots-${lib.versions.majorMinor wlroots.version}";
in

stdenv.mkDerivation rec {
  pname = "nixlytile";
  version = "git";

  passthru.providedSessions = [ "dwl" ];

src = fetchgit {
  url = "https://github.com/aCeTotal/nixlytile.git";
  rev = "HEAD";
  sha256 = "sha256-T/MiyseHHbNB965GtAJpzmUKlMYytQZgD0tsu7M9NfA=";
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

    # wallpapers
    if [ -d wallpapers ]; then
      mkdir -p $out/share/dwl/wallpapers
      cp -r wallpapers/* $out/share/dwl/wallpapers/
    fi

    # desktop entry for display managers
    mkdir -p $out/share/wayland-sessions
    cat > $out/share/wayland-sessions/dwl.desktop <<EOF
[Desktop Entry]
Name=dwl
Comment=Wayland compositor for NixlyOS (nixlytile), based on DWM/DWL.
Exec=dwl
Type=Application
DesktopNames=dwl
X-GDM-SessionRegisters=true
EOF

    wrapProgram $out/bin/dwl \
      --prefix PATH : ${lib.makeBinPath [ swaybg brightnessctl ]} \
      --prefix XDG_DATA_DIRS : "${papirus-icon-theme}/share:${adwaita-icon-theme}/share:${hicolor-icon-theme}/share"

    runHook postInstall
  '';

  meta = with lib; {
    description = "Custom dwl fork (nixlytile)";
    homepage = "https://github.com/aCeTotal/nixlytile";
    license = licenses.gpl3Plus;
    platforms = platforms.linux;
    mainProgram = "dwl";
  };
}

