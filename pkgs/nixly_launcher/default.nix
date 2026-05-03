{ lib
, rustPlatform
, src
, pkg-config
, cmake
, wayland-scanner
, makeWrapper
, wayland
, wayland-protocols
, wlr-protocols
, libxkbcommon
, libGL
, libglvnd
, mesa
, libdrm
, libgbm
, fontconfig
, freetype
, harfbuzz
, dbus
, systemd
, xdg-utils
}:

let
  runtimeLibs = [
    wayland
    libxkbcommon
    libGL
    libglvnd
    mesa
    libdrm
    libgbm
    fontconfig
    freetype
  ];

  runtimePathPkgs = [
    fontconfig
    xdg-utils
  ];
in
rustPlatform.buildRustPackage {
  pname = "nixly_launcher";
  version = "0.1.0";

  inherit src;

  cargoLock = {
    lockFile = src + "/Cargo.lock";
  };

  nativeBuildInputs = [
    pkg-config
    cmake
    wayland-scanner
    makeWrapper
  ];

  buildInputs = [
    wayland
    wayland-protocols
    wlr-protocols
    libxkbcommon
    libGL
    libglvnd
    mesa
    libdrm
    libgbm
    fontconfig
    freetype
    harfbuzz
    dbus
    systemd
  ];

  WAYLAND_PROTOCOLS_DIR = "${wayland-protocols}/share/wayland-protocols";
  WLR_PROTOCOLS_DIR = "${wlr-protocols}/share/wlr-protocols";

  postFixup = ''
    for bin in $out/bin/*; do
      wrapProgram "$bin" \
        --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath runtimeLibs}" \
        --prefix PATH : "${lib.makeBinPath runtimePathPkgs}"
    done

    # systemd user service — auto-starts the daemon when the user's
    # graphical session comes up (compositors that activate
    # graphical-session.target via systemd will start it automatically).
    mkdir -p $out/share/systemd/user
    cat > $out/share/systemd/user/nixly-launcher.service <<EOF
    [Unit]
    Description=nixly_launcher daemon (Wayland app launcher)
    PartOf=graphical-session.target
    After=graphical-session.target

    [Service]
    Type=simple
    ExecStart=$out/bin/appd
    Restart=on-failure
    RestartSec=3
    StandardOutput=journal
    StandardError=journal

    [Install]
    WantedBy=graphical-session.target
    EOF
  '';

  meta = with lib; {
    description = "Daemon + trigger Wayland launcher with layer-shell + OpenGL";
    mainProgram = "appd";
    platforms = platforms.linux;
    license = with licenses; [ mit asl20 ];
  };
}
