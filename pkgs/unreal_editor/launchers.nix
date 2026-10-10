{
  lib,
  stdenv,
  imagemagick,
  libicns,
  addDriverRunpath,
  alsa-lib,
  at-spi2-atk,
  at-spi2-core,
  atk,
  bzip2,
  cairo,
  cups,
  curl,
  dbus,
  expat,
  fontconfig,
  freetype,
  gdk-pixbuf,
  glib,
  gtk3,
  harfbuzz,
  icu,
  krb5,
  libdecor,
  libdrm,
  libepoxy,
  libffi,
  libgbm,
  libglvnd,
  libice,
  libjack2,
  libpulseaudio,
  libsecret,
  libsm,
  libunwind,
  libusb1,
  libx11,
  libxcb,
  libxcomposite,
  libxcursor,
  libxdamage,
  libxext,
  libxfixes,
  libxi,
  libxinerama,
  libxkbcommon,
  libxkbfile,
  libxml2,
  libxrandr,
  libxrender,
  libxscrnsaver,
  libxtst,
  libxxf86vm,
  ncurses,
  nspr,
  nss,
  openssl,
  pango,
  pipewire,
  readline,
  sqlite,
  systemd,
  util-linux,
  vulkan-loader,
  wayland,
  xz,
  zlib,
  bash,
  bubblewrap,
  coreutils,
  findutils,
  gawk,
  git,
  gnugrep,
  gnused,
  procps,
  which,
  xdg-user-dirs,
  xdg-utils,
}:

let
  runtimeLibs = [
    stdenv.cc.cc.lib
    addDriverRunpath.driverLink
    alsa-lib
    at-spi2-atk
    at-spi2-core
    atk
    bzip2
    cairo
    cups
    curl
    dbus
    expat
    fontconfig
    freetype
    gdk-pixbuf
    glib
    gtk3
    harfbuzz
    icu
    krb5
    libdecor
    libdrm
    libepoxy
    libffi
    libgbm
    libglvnd
    libice
    libjack2
    libpulseaudio
    libsecret
    libsm
    libunwind
    libusb1
    libx11
    libxcb
    libxcomposite
    libxcursor
    libxdamage
    libxext
    libxfixes
    libxi
    libxinerama
    libxkbcommon
    libxkbfile
    libxml2
    libxrandr
    libxrender
    libxscrnsaver
    libxtst
    libxxf86vm
    ncurses
    nspr
    nss
    openssl
    pango
    pipewire
    readline
    sqlite
    systemd
    util-linux
    vulkan-loader
    wayland
    xz
    zlib
  ];

  runtimeBins = [
    bash
    coreutils
    findutils
    gawk
    git
    gnugrep
    gnused
    procps
    which
    xdg-user-dirs
    xdg-utils
  ];

  entryPoints = {
    UnrealEditor = "Engine/Binaries/Linux/UnrealEditor";
    UnrealEditor-Cmd = "Engine/Binaries/Linux/UnrealEditor-Cmd";
    UnrealPak = "Engine/Binaries/Linux/UnrealPak";
    UnrealInsights = "Engine/Binaries/Linux/UnrealInsights";
    RunUAT = "Engine/Build/BatchFiles/RunUAT.sh";
    RunUBT = "Engine/Build/BatchFiles/RunUBT.sh";
  };
in
{
  inherit runtimeLibs;

  # Shell snippet installing launchers for "$engine".
  install =
    {
      id,
      name,
      comment,
      driver,
      state,
      resources,
    }:
    ''
      interp="$(cat ${stdenv.cc}/nix-support/dynamic-linker)"

      ide="$out/libexec/${id}"
      install -dm755 "$ide"
      substitute ${./code.sh} "$ide/code" \
        --replace-fail "#!/usr/bin/env bash" "#!${bash}/bin/bash"
      chmod +x "$ide/code"

      install -dm755 "$out/bin"
      ${lib.concatStringsSep "\n" (
        lib.mapAttrsToList (bin: rel: ''
          substitute ${./launcher.sh} "$out/bin/${bin}" \
            --replace-fail "#!/usr/bin/env bash" "#!${bash}/bin/bash" \
            --replace-fail "@engine@" "$engine" \
            --replace-fail "@exe@" "${rel}" \
            --replace-fail "@driver@" '${driver}' \
            --replace-fail "@state@" "${state}" \
            --replace-fail "@libs@" "${lib.makeLibraryPath runtimeLibs}" \
            --replace-fail "@path@" "${lib.makeBinPath runtimeBins}" \
            --replace-fail "@ide@" "$ide" \
            --replace-fail "@libdecorplugins@" "${libdecor}/lib/libdecor/plugins-1" \
            --replace-fail "@ld64@" "$(dirname "$interp")" \
            --replace-fail "@bwrap@" "${bubblewrap}/bin/bwrap"
          chmod +x "$out/bin/${bin}"
        '') entryPoints
      )}

      icon="${resources}/Linux/UnrealEngine.png"
      install -dm755 "$TMPDIR/icns"
      if ${libicns}/bin/icns2png -x -o "$TMPDIR/icns" "${resources}/Mac/UnrealEngine.icns" >/dev/null 2>&1; then
        largest="$(find "$TMPDIR/icns" -name '*.png' -printf '%s %p\n' | sort -n | tail -n1 | cut -d' ' -f2-)"
        if [ -n "$largest" ]; then
          icon="$largest"
        fi
      fi
      echo "icon source: $icon ($(${imagemagick}/bin/magick identify -format '%wx%h' "$icon"))"

      for size in 32 48 64 128 256 512; do
        install -dm755 "$out/share/icons/hicolor/''${size}x''${size}/apps"
        ${imagemagick}/bin/magick "$icon" -resize "''${size}x''${size}" \
          "$out/share/icons/hicolor/''${size}x''${size}/apps/${id}.png"
      done

      install -dm755 "$out/share/applications"
      cat > "$out/share/applications/${id}.desktop" <<DESKTOP
      [Desktop Entry]
      Type=Application
      Name=${name}
      GenericName=Game Engine Editor
      Comment=${comment}
      Exec=$out/bin/UnrealEditor %f
      Icon=${id}
      Terminal=false
      StartupNotify=true
      StartupWMClass=UnrealEditor
      Categories=Development;IDE;Graphics;3DGraphics;
      Keywords=Unreal;UE5;Game;Engine;Editor;
      DESKTOP
    '';
}
