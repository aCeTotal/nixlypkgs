{
  lib,
  stdenv,
  stdenvNoCC,
  fetchurl,
  unzip,
  patchelf,
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
  version = "5.8.0";
  base = "https://aceclan.no/derivations_source/UE5/${version}";

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
stdenvNoCC.mkDerivation {
  pname = "unreal-editor";
  inherit version;

  srcs = [
    (fetchurl {
      url = "${base}/Linux_Unreal_Engine_${version}.zip";
      hash = "sha256-1vykNfRUFQiwUq/rfPe4g0TuSokUpPka5J9T6gTtkXQ=";
    })
    (fetchurl {
      url = "${base}/Linux_Bridge_${version}_2025.0.1.zip";
      hash = "sha256-iycPft3pxCHgT4+5GOQVNzWgEJdmn1Lmqsq39en28kg=";
    })
    (fetchurl {
      url = "${base}/Linux_Fab_${version}_0.0.13.zip";
      hash = "sha256-Cy2ynW7/tkPWSDiNmkIdzC030EEA8NcotzjKuHTX5c0=";
    })
  ];

  nativeBuildInputs = [
    unzip
    patchelf
    imagemagick
    libicns
  ];

  dontUnpack = true;

  dontFixup = true;

  installPhase = ''
    runHook preInstall

    engine="$out/opt/UnrealEngine"
    install -dm755 "$engine"

    for archive in $srcs; do
      echo "extracting $archive"
      unzip -qq -o "$archive" -d "$engine"
    done

    find "$engine" \( -name '*.debug' -o -name '*.sym' -o -name '*.pdb' \) -delete
    rm -rf \
      "$engine/Engine/Binaries/Android" \
      "$engine/Engine/Binaries/LinuxArm64" \
      "$engine/Engine/Binaries/ThirdParty/DotNet/10.0/linux-arm64" \
      "$engine/Engine/Intermediate/Build/Android" \
      "$engine/Engine/Intermediate/Build/LinuxArm64"

    chmod -R u+w "$engine"
    chmod +x "$engine/Engine/Binaries/ThirdParty/DotNet/10.0/linux-x64/dotnet"
    find "$engine" -type f -name '*.sh' -exec chmod +x {} +

    interp="$(cat ${stdenv.cc}/nix-support/dynamic-linker)"
    libs="${lib.makeLibraryPath runtimeLibs}"
    patched=0
    while IFS= read -r -d "" f; do
      if [ -n "$(patchelf --print-interpreter "$f" 2>/dev/null)" ]; then
        patchelf --set-interpreter "$interp" "$f"
        old="$(patchelf --print-rpath "$f" 2>/dev/null || true)"
        patchelf --set-rpath "''${old:+$old:}$libs" "$f"
        patched=$((patched + 1))
      fi
    done < <(find "$engine" -type f -perm -u+x -print0)
    echo "patched interpreter and rpath on $patched executables"

    # Bridge's node-bifrost ships without the exec bit and cannot be patchelfed
    # (pkg-style binary, appended payload breaks). The launcher binds a real
    # ld.so over /lib64 so its stock interpreter resolves.
    chmod +x "$engine/Engine/Plugins/Bridge/ThirdParty/Linux/node-bifrost"

    find "$engine" -type f -name '*.sh' \
      -exec sed -i '1s|^#!/bin/bash|#!${bash}/bin/bash|' {} +

    ide="$out/libexec/unreal-editor"
    install -dm755 "$ide"
    substitute ${./code.sh} "$ide/code" \
      --replace-fail "#!/usr/bin/env bash" "#!${bash}/bin/bash"
    chmod +x "$ide/code"

    install -dm755 "$out/bin"
    ${lib.concatStringsSep "\n" (
      lib.mapAttrsToList (name: rel: ''
        substitute ${./launcher.sh} "$out/bin/${name}" \
          --replace-fail "#!/usr/bin/env bash" "#!${bash}/bin/bash" \
          --replace-fail "@engine@" "$engine" \
          --replace-fail "@exe@" "${rel}" \
          --replace-fail "@libs@" "${lib.makeLibraryPath runtimeLibs}" \
          --replace-fail "@path@" "${lib.makeBinPath runtimeBins}" \
          --replace-fail "@ide@" "$ide" \
          --replace-fail "@libdecorplugins@" "${libdecor}/lib/libdecor/plugins-1" \
          --replace-fail "@ld64@" "$(dirname "$interp")" \
          --replace-fail "@bwrap@" "${bubblewrap}/bin/bwrap"
        chmod +x "$out/bin/${name}"
      '') entryPoints
    )}

    icns="$engine/Engine/Source/Runtime/Launch/Resources/Mac/UnrealEngine.icns"
    src="$engine/Engine/Source/Runtime/Launch/Resources/Linux/UnrealEngine.png"
    install -dm755 "$TMPDIR/icns"
    if icns2png -x -o "$TMPDIR/icns" "$icns" >/dev/null 2>&1; then
      largest="$(ls -S "$TMPDIR/icns"/*.png 2>/dev/null | head -n1)"
      if [ -n "$largest" ]; then
        src="$largest"
      fi
    fi
    echo "icon source: $src ($(magick identify -format '%wx%h' "$src"))"

    for size in 32 48 64 128 256 512; do
      install -dm755 "$out/share/icons/hicolor/''${size}x''${size}/apps"
      magick "$src" -resize "''${size}x''${size}" \
        "$out/share/icons/hicolor/''${size}x''${size}/apps/unreal-editor.png"
    done

    install -dm755 "$out/share/applications"
    cat > "$out/share/applications/unreal-editor.desktop" <<DESKTOP
    [Desktop Entry]
    Type=Application
    Name=Unreal Editor
    GenericName=Game Engine Editor
    Comment=Unreal Engine ${version} editor
    Exec=$out/bin/UnrealEditor %f
    Icon=unreal-editor
    Terminal=false
    StartupNotify=true
    StartupWMClass=UnrealEditor
    Categories=Development;IDE;Graphics;3DGraphics;
    Keywords=Unreal;UE5;Game;Engine;Editor;
    DESKTOP

    runHook postInstall
  '';

  meta = {
    description = "Unreal Engine ${version} editor (Epic's prebuilt Linux installed build)";
    homepage = "https://www.unrealengine.com/";
    license = lib.licenses.unfree;
    platforms = [ "x86_64-linux" ];
    mainProgram = "UnrealEditor";
    hydraPlatforms = [ ];
  };
}
