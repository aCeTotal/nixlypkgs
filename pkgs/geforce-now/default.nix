{
  lib,
  stdenvNoCC,
  fetchurl,
  python3,
  flatpak,
  libnotify,
}:

stdenvNoCC.mkDerivation {
  pname = "geforce-now";
  version = "2026.05.08";

  # Only used for the official icons; the app itself is the
  # com.nvidia.geforcenow flatpak (see nixlyos/apps/geforce-now.nix).
  src = fetchurl {
    url = "https://international.download.nvidia.com/GFNLinux/GeForceNOWSetup.bin";
    hash = "sha256-kvpNdLB5mkDFUl/0SrohD85q4m1UB1PfiB+oxlg1JJQ=";
  };

  dontUnpack = true;
  dontBuild = true;

  nativeBuildInputs = [ python3 ];

  installPhase = ''
    runHook preInstall

    mkdir -p assets
    python3 ${./extract_pyinstaller_assets.py} "$src" assets

    install -Dm0644 assets/GFN-Logo.png $out/share/icons/hicolor/256x256/apps/com.nvidia.geforcenow.png

    mkdir -p $out/bin
    cat > $out/bin/geforce-now <<'LAUNCHER'
    #!/usr/bin/env bash
    set -euo pipefail
    FLATPAK=NIXLY_FLATPAK
    NOTIFY=NIXLY_NOTIFY

    # Self-install (user scope) if the boot-time system install has not
    # completed yet, so launching always works with zero manual steps.
    if ! "$FLATPAK" info com.nvidia.geforcenow >/dev/null 2>&1; then
      "$NOTIFY" "GeForce NOW" "Installing on first launch, this can take a few minutes..." || true
      "$FLATPAK" remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
      "$FLATPAK" remote-add --user --if-not-exists geforcenow https://international.download.nvidia.com/GFNLinux/flatpak/geforcenow.flatpakrepo
      if ! "$FLATPAK" install --user --noninteractive --or-update geforcenow com.nvidia.geforcenow; then
        "$NOTIFY" -u critical "GeForce NOW" "Install failed. Check your network connection." || true
        exit 1
      fi
    fi
    exec "$FLATPAK" run com.nvidia.geforcenow "$@"
    LAUNCHER
    chmod +x $out/bin/geforce-now

    substituteInPlace $out/bin/geforce-now \
      --replace-fail "NIXLY_FLATPAK" ${lib.escapeShellArg (lib.getExe flatpak)} \
      --replace-fail "NIXLY_NOTIFY" ${lib.escapeShellArg (lib.getExe' libnotify "notify-send")}

    # Same desktop-file ID as the flatpak export so menus dedupe to one entry.
    mkdir -p $out/share/applications
    cat > $out/share/applications/com.nvidia.geforcenow.desktop <<DESKTOP
    [Desktop Entry]
    Name=GeForce NOW
    GenericName=Cloud Gaming
    Comment=NVIDIA GeForce NOW cloud gaming
    Exec=$out/bin/geforce-now %U
    Icon=com.nvidia.geforcenow
    Terminal=false
    Type=Application
    Categories=Game;
    StartupWMClass=com.nvidia.geforcenow
    StartupNotify=true
    PrefersNonDefaultGPU=true
    X-KDE-RunOnDiscreteGpu=true
    DESKTOP

    runHook postInstall
  '';

  meta = {
    description = "NVIDIA GeForce NOW cloud gaming launcher (flatpak)";
    longDescription = ''
      Launcher and desktop entry for the native GeForce NOW Linux client,
      which NVIDIA ships as the com.nvidia.geforcenow flatpak. The upstream
      GeForceNOWSetup.bin is a PyInstaller installer that adds NVIDIA's
      flatpak remote and installs the app imperatively; on NixlyOS the
      nixlyos/apps/geforce-now.nix module does that declaratively via a
      systemd service. This derivation only extracts the official icons
      from the installer payload and provides a `flatpak run` wrapper.
    '';
    homepage = "https://www.nvidia.com/geforce-now/";
    license = lib.licenses.unfree;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "geforce-now";
  };
}
