# FHS sandbox that runs the unwrapped STM32CubeIDE tree.
# Everything the bundled JRE / GCC / gdbserver / SWT expect lives here.
# Wayland is the default backend; it falls back to XWayland automatically.
{ lib
, buildFHSEnv
, writeShellScript
, stm32cubeide-unwrapped
}:

let
  ide = stm32cubeide-unwrapped;

  # Prefer ST's own Wayland launcher when present, else the normal one.
  launcher = writeShellScript "stm32cubeide-launch" ''
    ide="${ide}/stm32cubeide"
    exe="$ide/stm32cubeide"
    [ -x "$ide/stm32cubeide_wayland" ] && exe="$ide/stm32cubeide_wayland"

    # ---- Wayland measures ------------------------------------------------
    # Native Wayland first, XWayland as fallback (GTK understands the list).
    export GDK_BACKEND="''${GDK_BACKEND:-wayland,x11}"
    # SWT/GTK3 explicitly (STM32CubeIDE is Eclipse/SWT).
    export SWT_GTK3="''${SWT_GTK3:-1}"
    # Java/SWT window handling under wlroots/Sway/Hyprland compositors.
    export _JAVA_AWT_WM_NONREPARENTING=1
    # Eclipse embedded browser (help/marketplace) via WebKitGTK.
    export WEBKIT_DISABLE_DMABUF_RENDERER=1
    # Don't route file dialogs through xdg-portal (avoids blank dialogs).
    export GTK_USE_PORTAL=0

    exec "$exe" "$@"
  '';
in
buildFHSEnv {
  name = "stm32cubeide";

  runScript = "${launcher}";

  targetPkgs = pkgs: with pkgs; [
    # GTK / GNOME stack
    gtk3
    glib
    gsettings-desktop-schemas
    gdk-pixbuf
    pango
    cairo
    atk
    at-spi2-core
    at-spi2-atk
    adwaita-icon-theme
    hicolor-icon-theme
    dconf

    # Eclipse embedded browser widget
    webkitgtk_4_1
    libsoup_3

    # Wayland + GL
    wayland
    wayland-protocols
    libxkbcommon
    libGL
    libglvnd
    mesa

    # X11 / XWayland fallback (SWT still links some Xlibs)
    libx11
    libxext
    libxtst
    libxrender
    libxi
    libxrandr
    libxfixes
    libxcursor
    libxcomposite
    libxdamage
    libxscrnsaver
    libxcb

    # Fonts
    fontconfig
    freetype
    dejavu_fonts

    # Bundled JRE / general runtime
    stdenv.cc.cc.lib
    zlib
    nss
    nspr
    expat
    dbus
    cups
    alsa-lib

    # ST-Link / J-Link probes + gdbserver
    libusb1
    systemd
    ncurses5

    # Misc tools the toolchain / scripts call
    coreutils
    which
    file
    gnused
    gnugrep
    gawk
    findutils
    procps
    gnumake
  ];

  extraInstallCommands = ''
    mkdir -p $out/share/applications
    cat > $out/share/applications/stm32cubeide.desktop <<DESKTOP
    [Desktop Entry]
    Type=Application
    Name=STM32CubeIDE
    GenericName=Embedded IDE
    Comment=STM32 IDE with integrated STM32CubeMX device configurator
    Exec=$out/bin/stm32cubeide %F
    Icon=stm32cubeide
    Terminal=false
    Categories=Development;IDE;Electronics;
    StartupWMClass=STM32CubeIDE
    StartupNotify=true
    MimeType=text/x-csrc;text/x-chdr;application/x-stm32cubeide-ioc;
    DESKTOP

    icon=$(find ${ide}/stm32cubeide -maxdepth 2 -name 'icon.xpm' -o -name '*.png' \
      | grep -iE 'icon' | head -n1 || true)
    if [ -n "$icon" ]; then
      install -Dm0644 "$icon" \
        "$out/share/pixmaps/stm32cubeide.''${icon##*.}"
    fi
  '';

  meta = with lib; {
    description = "STM32CubeIDE — Eclipse IDE with integrated STM32CubeMX (Wayland-ready, FHS-wrapped)";
    homepage = "https://www.st.com/en/development-tools/stm32cubeide.html";
    license = licenses.unfree;
    platforms = [ "x86_64-linux" ];
    mainProgram = "stm32cubeide";
  };
}
