# Unreal Engine 5.8.0 installed build (Epic's prebuilt Linux binaries).
#
# Not built from source: the archive already carries Epic's own clang 20.1.8
# toolchain, precompiled engine modules and a Zen store manifest, and it is
# marked Engine/Build/InstalledBuild.txt - so UnrealBuildTool treats the engine
# tree as read-only and redirects every write into the project directory and
# $HOME. That is what makes a Nix store install viable at all.
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
  # PATH for the engine and the tools it shells out to.
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

  # Loaded by the editor itself, by the CEF3 browser helper, by the bundled
  # CPython 3.11 and by the bundled .NET 10 runtime. None of these ship a
  # libstdc++ or glibc of their own.
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
    # xdg-user-dir: the editor resolves the default project directory with it.
    xdg-user-dirs
    xdg-utils
  ];

  # bin name -> path relative to the engine root
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

  # ~50 GiB of prebuilt binaries. Every stdenv fixup hook here would walk the
  # whole tree for no gain, and stripping would break Epic's crash reporter.
  dontFixup = true;

  installPhase = ''
    runHook preInstall

    engine="$out/opt/UnrealEngine"
    install -dm755 "$engine"

    # The engine archive is rooted at Engine/, and both plugin archives are
    # rooted at Engine/Plugins/ - they overlay onto the same tree with no
    # colliding paths.
    for archive in $srcs; do
      echo "extracting $archive"
      unzip -qq -o "$archive" -d "$engine"
    done

    # --- slimming ---------------------------------------------------------
    # Split debug info (10.5 GiB), Breakpad symbols (3.4 GiB) and PDBs, plus
    # the Android and Linux/arm64 target binaries and their prebuilt objects.
    # Engine/Intermediate/Build/Linux stays: it holds the UHT-generated headers
    # every game C++ module includes, and the objects that keep the first
    # "package a Linux build" from recompiling the whole engine.
    find "$engine" \( -name '*.debug' -o -name '*.sym' -o -name '*.pdb' \) -delete
    rm -rf \
      "$engine/Engine/Binaries/Android" \
      "$engine/Engine/Binaries/LinuxArm64" \
      "$engine/Engine/Binaries/ThirdParty/DotNet/10.0/linux-arm64" \
      "$engine/Engine/Intermediate/Build/Android" \
      "$engine/Engine/Intermediate/Build/LinuxArm64"

    # --- ELF fixup --------------------------------------------------------
    # Only the interpreter needs rewriting; shared objects are resolved through
    # LD_LIBRARY_PATH, which the launcher sets and every spawned worker
    # (ShaderCompileWorker, EpicWebHelper, UnrealBuildTool) inherits.
    #
    # A large part of the archive is extracted as 0555 (Epic's own binaries are
    # 0755), and patchelf needs to reopen the file for writing - without this
    # every third-party executable, dotnet and the bundled Python included,
    # silently keeps its /lib64 interpreter.
    chmod -R u+w "$engine"
    chmod +x "$engine/Engine/Binaries/ThirdParty/DotNet/10.0/linux-x64/dotnet"
    find "$engine" -type f -name '*.sh' -exec chmod +x {} +

    interp="$(cat ${stdenv.cc}/nix-support/dynamic-linker)"
    patched=0
    while IFS= read -r -d "" f; do
      if [ -n "$(patchelf --print-interpreter "$f" 2>/dev/null)" ]; then
        patchelf --set-interpreter "$interp" "$f"
        patched=$((patched + 1))
      fi
    done < <(find "$engine" -type f -perm -u+x -print0)
    echo "patched interpreter on $patched executables"

    # --- shebangs ----------------------------------------------------------
    # The batch files hardcode #!/bin/bash, which does not exist on NixOS. The
    # editor spawns Build.sh through posix_spawnp(), so this surfaces as
    # "Failed to launch Unreal Build Tool" rather than as a shell error.
    find "$engine" -type f -name '*.sh' \
      -exec sed -i '1s|^#!/bin/bash|#!${bash}/bin/bash|' {} +

    # --- source code editor -------------------------------------------------
    # Kept out of $out/bin so it is only on the PATH the launcher builds for
    # the engine, never on the user's.
    ide="$out/libexec/unreal-editor"
    install -dm755 "$ide"
    substitute ${./code.sh} "$ide/code" \
      --replace-fail "#!/usr/bin/env bash" "#!${bash}/bin/bash"
    chmod +x "$ide/code"

    # --- launchers --------------------------------------------------------
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
          --replace-fail "@bwrap@" "${bubblewrap}/bin/bwrap"
        chmod +x "$out/bin/${name}"
      '') entryPoints
    )}

    # --- icon -------------------------------------------------------------
    # The .icns holds the full-resolution UE artwork (ImageMagick has no ICNS
    # coder, hence icns2png); the Linux .png upstream ships is a 96px stand-in
    # and is only the fallback.
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

    # --- desktop entry ----------------------------------------------------
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
    # 40 GiB source + ~51 GiB output; nothing a binary cache should carry.
    hydraPlatforms = [ ];
  };
}
