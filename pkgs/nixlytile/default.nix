{ lib
, stdenv
, fetchFromGitHub
, pkg-config
, makeWrapper
, gawk
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
    rev = "main";
    hash = "sha256-RLivDVYUsA+8/SBQSMsHzv5Nbfpx5AgA77SL3TfiiTw=";
  };

  nativeBuildInputs = [
    pkg-config
    wayland
    wayland-scanner
    wayland-protocols
    makeWrapper
    gawk
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

    # Generate game_params.conf from game_launch_params.h if it exists
    if [ -f game_launch_params.h ]; then
      echo "Generating game_params.conf from game_launch_params.h..."
      mkdir -p $out/share/nixlytile
      echo "# Auto-generated from game_launch_params.h" > $out/share/nixlytile/game_params.conf
      echo "# Format: APPID|nvidia_params|amd_params|amd_amdvlk_params|intel_params" >> $out/share/nixlytile/game_params.conf
      echo "" >> $out/share/nixlytile/game_params.conf

      ${gawk}/bin/awk '
        /\.game_id *= *"/ {
          match($0, /"[^"]+"/);
          game_id = substr($0, RSTART+1, RLENGTH-2)
        }
        /\.nvidia *= *"/ {
          match($0, /"[^"]*"/);
          nvidia = substr($0, RSTART+1, RLENGTH-2)
        }
        /\.amd *= *"/ && !/\.amd_amdvlk/ {
          match($0, /"[^"]*"/);
          amd = substr($0, RSTART+1, RLENGTH-2)
        }
        /\.amd_amdvlk *= *"/ {
          match($0, /"[^"]*"/);
          amdvlk = substr($0, RSTART+1, RLENGTH-2)
        }
        /\.intel *= *"/ {
          match($0, /"[^"]*"/);
          intel = substr($0, RSTART+1, RLENGTH-2)
        }
        /^\t\},$/ || /^\t\}$/ {
          if (game_id != "" && game_id !~ /NULL/) {
            print game_id "|" nvidia "|" amd "|" amdvlk "|" intel
          }
          game_id = ""; nvidia = ""; amd = ""; amdvlk = ""; intel = ""
        }
      ' game_launch_params.h >> $out/share/nixlytile/game_params.conf
    fi

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
