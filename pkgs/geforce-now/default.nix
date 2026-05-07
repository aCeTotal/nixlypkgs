{
  lib,
  stdenvNoCC,
  fetchurl,
  makeWrapper,
  python3,
  # Browser executable resolved from PATH at runtime. Must accept
  # `--app=<url>` (any Chromium-derived browser: chromium, google-chrome,
  # brave, vivaldi, microsoft-edge, etc.). Kept as a plain string so we
  # don't pull a browser into this derivation's closure (chromium from
  # nixpkgs is often uncached and would build from source).
  browserCommand ? "chromium",
  # Page opened in app mode. Default is the GFN web client.
  url ? "https://play.geforcenow.com/",
}:

stdenvNoCC.mkDerivation {
  pname = "geforce-now";
  version = "1.0.0";

  src = fetchurl {
    url = "https://international.download.nvidia.com/GFNLinux/GeForceNOWSetup.bin";
    hash = "sha256-kvpNdLB5mkDFUl/0SrohD85q4m1UB1PfiB+oxlg1JJQ=";
  };

  dontUnpack = true;
  dontBuild = true;

  nativeBuildInputs = [ makeWrapper python3 ];

  installPhase = ''
    runHook preInstall

    mkdir -p assets
    python3 ${./extract_pyinstaller_assets.py} "$src" assets

    install -Dm0644 assets/GFN-Logo.png            $out/share/icons/hicolor/256x256/apps/geforce-now.png
    install -Dm0644 assets/GFN-Tile.png            $out/share/pixmaps/geforce-now-tile.png
    install -Dm0644 assets/GFN-Hero.png            $out/share/pixmaps/geforce-now-hero.png
    install -Dm0644 assets/GFN-Hero-logo.png       $out/share/pixmaps/geforce-now-hero-logo.png
    install -Dm0644 assets/GFN-Recent-Tile.png     $out/share/pixmaps/geforce-now-recent.png
    install -Dm0644 assets/NVIDIA_GeForceNOW_Logo.png $out/share/pixmaps/nvidia-geforce-now-logo.png

    mkdir -p $out/bin
    cat > $out/bin/geforce-now <<'LAUNCHER'
    #!/usr/bin/env bash
    set -euo pipefail
    : "''${GEFORCE_NOW_BROWSER:=NIXLY_BROWSER}"
    if ! command -v "$GEFORCE_NOW_BROWSER" >/dev/null 2>&1; then
      echo "geforce-now: browser '$GEFORCE_NOW_BROWSER' not in PATH." >&2
      echo "  install chromium/google-chrome/brave/etc., or set GEFORCE_NOW_BROWSER." >&2
      exit 127
    fi
    exec "$GEFORCE_NOW_BROWSER" \
      --app=NIXLY_URL \
      --class=geforce-now \
      --name=geforce-now \
      --user-data-dir="''${XDG_DATA_HOME:-$HOME/.local/share}/geforce-now" \
      "$@"
    LAUNCHER
    chmod +x $out/bin/geforce-now

    substituteInPlace $out/bin/geforce-now \
      --replace-fail "NIXLY_BROWSER" ${lib.escapeShellArg browserCommand} \
      --replace-fail "NIXLY_URL" ${lib.escapeShellArg url}

    mkdir -p $out/share/applications
    cat > $out/share/applications/geforce-now.desktop <<DESKTOP
    [Desktop Entry]
    Name=GeForce NOW
    GenericName=Cloud Gaming
    Comment=NVIDIA GeForce NOW cloud gaming (PWA)
    Exec=$out/bin/geforce-now %U
    Icon=geforce-now
    Terminal=false
    Type=Application
    Categories=Game;
    StartupWMClass=geforce-now
    StartupNotify=true
    PrefersNonDefaultGPU=true
    X-KDE-RunOnDiscreteGpu=true
    DESKTOP

    runHook postInstall
  '';

  meta = {
    description = "NVIDIA GeForce NOW cloud gaming PWA launcher";
    longDescription = ''
      Native NixOS replacement for NVIDIA's GeForceNOWSetup.bin.
      The upstream installer is a PyInstaller-bundled Python program that
      creates a Chromium PWA shortcut. This derivation extracts the icons
      from the upstream payload and installs an equivalent launcher
      (chromium --app=<url>) plus a desktop entry, skipping the imperative
      installer entirely. Browser is resolved from PATH at runtime; install
      chromium/google-chrome/brave/etc. separately or set GEFORCE_NOW_BROWSER.
    '';
    homepage = "https://www.nvidia.com/geforce-now/";
    license = lib.licenses.unfree;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "geforce-now";
  };
}
