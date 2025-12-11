{
  lib,
  stdenv,
  stdenvAdapters,
  fetchFromGitHub,
  hyprlandSrc ? null,
  pkg-config,
  makeWrapper,
  cmake,
  meson,
  ninja,
  aquamarine,
  binutils,
  cairo,
  epoll-shim,
  git,
  glaze,
  hyprcursor,
  hyprgraphics,
  hyprland-qtutils,
  hyprlang,
  hyprutils,
  hyprwayland-scanner,
  libGL,
  libdrm,
  libexecinfo,
  libinput,
  libuuid,
  libxkbcommon,
  libgbm,
  pango,
  pciutils,
  pkgconf,
  python3,
  re2,
  systemd,
  tomlplusplus,
  wayland,
  wayland-protocols,
  wayland-scanner,
  xorg,
  xwayland,
  debug ? false,
  enableXWayland ? true,
  withSystemd ? lib.meta.availableOn stdenv.hostPlatform systemd,
  wrapRuntimeDeps ? true,
  # deprecated flags
  nvidiaPatches ? false,
  hidpiXWayland ? false,
  enableNvidiaPatches ? false,
  legacyRenderer ? false,
}:
let
  inherit (builtins)
    foldl'
    pathExists
    ;
  inherit (lib.asserts) assertMsg;
  inherit (lib.attrsets) mapAttrsToList;
  inherit (lib.lists)
    concatLists
    optionals
    ;
  inherit (lib.strings)
    makeBinPath
    optionalString
    mesonBool
    mesonEnable
    ;
  inherit (lib.trivial)
    importJSON
    ;

  infoPath = ./info.json;
  info = if pathExists infoPath then importJSON infoPath else {
    branch = "unknown";
    commit_hash = "unknown";
    commit_message = "unknown";
    date = "unknown";
    tag = "git";
  };

  # possibility to add more adapters in the future, such as keepDebugInfo,
  # which would be controlled by the `debug` flag
  # Condition on darwin to avoid breaking eval for darwin in CI,
  # even though darwin is not supported anyway.
  adapters = lib.optionals (!stdenv.targetPlatform.isDarwin) [
    stdenvAdapters.useMoldLinker
  ];

  customStdenv = foldl' (acc: adapter: adapter acc) stdenv adapters;
in
assert assertMsg (!nvidiaPatches) "The option `nvidiaPatches` has been removed.";
assert assertMsg (!enableNvidiaPatches) "The option `enableNvidiaPatches` has been removed.";
assert assertMsg (!hidpiXWayland)
  "The option `hidpiXWayland` has been removed. Please refer https://wiki.hyprland.org/Configuring/XWayland";
assert assertMsg (
  !legacyRenderer
) "The option `legacyRenderer` has been removed. Legacy renderer is no longer supported.";

customStdenv.mkDerivation (finalAttrs: {
  pname = "nixly" + optionalString debug "-debug";
  version = "git";

  src = if hyprlandSrc != null then hyprlandSrc else fetchFromGitHub {
    owner = "aCeTotal";
    repo = "Hyprland";
    fetchSubmodules = true;
    rev = "2ca7ad7efc1e20588af5c823ee46f23afad6cf91";
    hash = "sha256-KAwcM3w98TxiGlBnWYxhTdHM1vZZhzeeXaEE647REZ0=";
  };

  postPatch = ''
    # Fix hardcoded paths to /usr installation
    sed -i "s#/usr#$out#" src/render/OpenGL.cpp

    # Remove extra @PREFIX@ to fix pkg-config paths
    sed -i "s#@PREFIX@/##g" hyprland.pc.in
  '';

  # variables used by generateVersion.sh script, and shown in `hyprctl version`
  BRANCH = info.branch;
  COMMITS = info.commit_hash;
  DATE = info.date;
  DIRTY = "";
  HASH = info.commit_hash;
  MESSAGE = info.commit_message;
  TAG = info.tag;

  depsBuildBuild = [
    # to find wayland-scanner when cross-compiling
    pkg-config
  ];

  nativeBuildInputs = [
    hyprwayland-scanner
    makeWrapper
    meson
    ninja
    pkg-config
    wayland-scanner
    # for udis86
    cmake
    python3
  ];

  outputs = [
    "out"
    "man"
    "dev"
  ];

  buildInputs = concatLists [
    [
      aquamarine
      cairo
      glaze
      git
      hyprcursor.dev
      hyprgraphics
      hyprlang
      hyprutils
      libGL
      libdrm
      libinput
      libuuid
      libxkbcommon
      libgbm
      pango
      pciutils
      re2
      tomlplusplus
      wayland
      wayland-protocols
      xorg.libXcursor
    ]
    (optionals customStdenv.hostPlatform.isBSD [ epoll-shim ])
    (optionals customStdenv.hostPlatform.isMusl [ libexecinfo ])
    (optionals enableXWayland [
      xorg.libxcb
      xorg.libXdmcp
      xorg.xcbutilerrors
      xorg.xcbutilwm
      xwayland
    ])
    (optionals withSystemd [ systemd ])
  ];

  mesonBuildType = if debug then "debug" else "release";

  dontStrip = debug;
  strictDeps = true;

  mesonFlags = concatLists [
    (mapAttrsToList mesonEnable {
      "xwayland" = enableXWayland;
      "systemd" = withSystemd;
      "uwsm" = false;
      "hyprpm" = false;
    })
    (mapAttrsToList mesonBool {
      # PCH provides no benefits when building with Nix
      "b_pch" = false;
      "tracy_enable" = false;
    })
  ];

  postInstall = ''
    ${optionalString wrapRuntimeDeps ''
      wrapProgram $out/bin/Hyprland \
        --suffix PATH : ${
          makeBinPath [
            binutils
            hyprland-qtutils
            pciutils
            pkgconf
          ]
        }
    ''}
  '';

  passthru = {
    providedSessions = [ "hyprland" ];
    updateScript = ./update.sh;
  };

  meta = {
    homepage = "https://github.com/aCeTotal/Hyprland";
    description = "NixlyOS Hyprland fork (dynamic tiling Wayland compositor)";
    license = lib.licenses.bsd3;
    teams = [ lib.teams.hyprland ];
    mainProgram = "Hyprland";
    platforms = lib.platforms.linux ++ lib.platforms.freebsd;
  };
})
