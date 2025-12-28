{ pkgs }:

let
  lib = pkgs.lib;
  stdenv = pkgs.stdenv;
in
stdenv.mkDerivation rec {
  pname = "speedtree-modeler";
  version = "10.1.0";

  src = pkgs.fetchurl {
    # Upstream prebuilt tarball
    url = "https://cdn-files.hexagon.unity.com/public/files/speedtree/SpeedTree_Modeler_v${version}_Linux.tar.gz";
    hash = "sha256-UxNiB1RwLj7fiMuAPKQW1fMBtoWIGUKNnwUkPy2koGo=";
  };

  nativeBuildInputs = [
    pkgs.makeWrapper
    pkgs.patchelf
  ];

  # We provide our own launcher and avoid Qt wrapper env logic
  dontWrapQtApps = true;

  buildInputs = with pkgs; [
    stdenv.cc.cc.lib
    zlib
    libGL
    libGLU
    freetype
    fontconfig
    alsa-lib
    libdrm
    dbus

    # X11 / XCB stack
    xorg.libX11
    xorg.libXext
    xorg.libXrender
    xorg.libXrandr
    xorg.libXinerama
    xorg.libXxf86vm
    xorg.libSM
    xorg.libICE
    xorg.libXi
    xorg.libXcursor
    xorg.libXfixes
    xorg.libXdamage
    xorg.libXcomposite
    xorg.libxcb
    xorg.libXau
    xorg.libXdmcp
    libxkbcommon
    xorg.xcbutil
    xorg.xcbutilimage
    xorg.xcbutilkeysyms
    xorg.xcbutilrenderutil
    xorg.xcbutilwm
    xorg.xcbutilcursor

    # Qt 6 runtime for plugins needing Qt libs
    # We rely on bundled Qt; include system libs only
    sqlite
    xkeyboard_config
  ];

  # We'll patch binaries manually and avoid autoPatchelf
  dontAutoPatchelf = true;

  dontUnpack = true;
  dontPatch = true;

  installPhase = ''
    runHook preInstall

    install -dm755 "$out/opt/speedtree"

    workdir="$(mktemp -d)"
    tar -xzf "${src}" -C "$workdir"

    # Try to locate the inner directory robustly
    innerRoot=""

    # Common structure: SpeedTree_Modeler_v*/SpeedTree_Modeler_v*
    topCandidate="$(find "$workdir" -maxdepth 2 -type d -name 'SpeedTree_Modeler_v*_Linux' -print -quit || true)"
    if [ -n "$topCandidate" ]; then
      innerRoot="$(find "$topCandidate" -mindepth 1 -maxdepth 1 -type d -name 'SpeedTree_Modeler_v*' -print -quit || true)"
    fi

    # Fallback: find a 'linux' dir and take its parent
    if [ -z "$innerRoot" ]; then
      linuxDir="$(find "$workdir" -maxdepth 4 -type d -name linux -print -quit || true)"
      if [ -n "$linuxDir" ]; then
        innerRoot="$(dirname "$linuxDir")"
      fi
    fi

    # Fallback: find the 'data' file and take its directory
    if [ -z "$innerRoot" ]; then
      dataDir="$(find "$workdir" -maxdepth 4 -type f -name data -print -quit || true)"
      if [ -n "$dataDir" ]; then
        innerRoot="$(dirname "$dataDir")"
      fi
    fi

    if [ -z "$innerRoot" ] || [ ! -d "$innerRoot" ]; then
      echo "Could not locate inner SpeedTree directory after extraction" >&2
      echo "Archive structure may have changed; please report layout." >&2
      echo "Workdir contents:" >&2
      find "$workdir" -maxdepth 3 -print >&2 || true
      exit 1
    fi

    cp -a "$innerRoot"/. "$out/opt/speedtree/"

    cd "$out/opt/speedtree"

    # Unpack additional data file if present
    if [ -f data ]; then
      tar -zxf data > /dev/null 2>&1 || true
    fi

    # Patch binaries and shared objects to find bundled libs and system libs
    rpath_base="$out/opt/speedtree/linux/lib:${lib.makeLibraryPath buildInputs}"
    if [ -f linux/SpeedTree_Modeler ]; then
      chmod +x linux/SpeedTree_Modeler || true
      ${pkgs.patchelf}/bin/patchelf --set-interpreter ${stdenv.cc.bintools.dynamicLinker} linux/SpeedTree_Modeler || true
    fi
    while IFS= read -r -d $'\0' f; do
      if file -b "$f" | grep -q ELF; then
        ${pkgs.patchelf}/bin/patchelf --set-rpath "$rpath_base" "$f" || true
      fi
    done < <(find linux -type f -print0)

    # Launcher script that mirrors upstream behavior, adapted for NixOS
    libPath="${lib.makeLibraryPath buildInputs}"
    cat > "$out/opt/speedtree/speedtree.sh" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail

# Change to SpeedTree directory
CANONPATH="$(readlink -f "$0")"
CANONPATH="$(dirname "$CANONPATH")"
cd "$CANONPATH"

# Set up new library path (include bundled libs + system libs)
# Temporarily disable 'nounset' to allow empty LD_LIBRARY_PATH
set +u
export LD_LIBRARY_PATH="$CANONPATH"/linux/lib:__LIBPATH__:"$LD_LIBRARY_PATH"
set -u

# Set Qt plugin paths to bundled plugins
export QT_PLUGIN_PATH="$CANONPATH/linux/plugins"
export QT_QPA_PLATFORM_PLUGIN_PATH="$CANONPATH/linux/plugins/platforms"
export QT_QPA_PLATFORM="xcb"
export XKB_CONFIG_ROOT="__XKBROOT__"
# export QT_DEBUG_PLUGINS=0

# Uncomment to use license file instead of app preferences
# export idvinc_LICENSE="/path/to/license.lic"

# Run SpeedTree Modeler
exec "./linux/SpeedTree_Modeler" "$@"
EOS
    substituteInPlace "$out/opt/speedtree/speedtree.sh" \
      --replace "__LIBPATH__" "$libPath" \
      --replace "__XKBROOT__" "${pkgs.xkeyboard_config}/share/X11/xkb"
    chmod +x "$out/opt/speedtree/speedtree.sh"

    # User-facing entry in PATH
    install -dm755 "$out/bin"
    ln -s "$out/opt/speedtree/speedtree.sh" "$out/bin/speedtree-modeler"

    # .desktop entry for launchers like rofi
    install -dm755 "$out/share/applications"
    cat > "$out/share/applications/speedtree-modeler.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=SpeedTree Modeler
Comment=SpeedTree Modeler 10
Exec=$out/bin/speedtree-modeler
Terminal=false
Categories=Graphics;3DGraphics;
EOF

    runHook postInstall
  '';

  meta = with lib; {
    description = "SpeedTree Modeler (prebuilt binary) packaged for NixOS";
    homepage = "https://speedtree.com/";
    platforms = [ "x86_64-linux" ];
    license = licenses.unfree;
    maintainers = [];
  };
}
