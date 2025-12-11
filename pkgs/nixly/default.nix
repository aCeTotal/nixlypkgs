{
  lib,
  stdenv,
  stdenvAdapters,
  fetchFromGitHub,
  hyprlandSrc ? null,
  pkg-config,
  makeWrapper,
  cmake,
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
  muparser,
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
  inherit (lib.lists)
    concatLists
    optionals
    ;
  inherit (lib.strings)
    makeBinPath
    optionalString
    ;
  inherit (lib.trivial)
    importJSON
    ;

  cmakeBool = name: value: "-D${name}=${if value then "ON" else "OFF"}";

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

  # variables used by build scripts and shown in `hyprctl version`
  GIT_BRANCH = info.branch;
  GIT_COMMITS = "0";
  GIT_COMMIT_HASH = info.commit_hash;
  GIT_COMMIT_MESSAGE = info.commit_message;
  GIT_COMMIT_DATE = info.date;
  GIT_DIRTY = "clean";
  GIT_TAG = info.tag;

  depsBuildBuild = [
    # to find wayland-scanner when cross-compiling
    pkg-config
  ];

  nativeBuildInputs = [
    hyprwayland-scanner
    makeWrapper
    ninja
    pkg-config
    wayland-scanner
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
      muparser
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

  cmakeBuildType = if debug then "Debug" else "Release";

  dontStrip = debug;
  strictDeps = true;

  cmakeFlags = [
    (cmakeBool "NO_XWAYLAND" (!enableXWayland))
    (cmakeBool "NO_SYSTEMD" (!withSystemd))
    "-DNO_HYPRPM=ON"
    "-DNO_UWSM=ON"
    "-DBUILD_TESTING=OFF"
    "-DWITH_TESTS=OFF"
    "-DCMAKE_DISABLE_PRECOMPILE_HEADERS=ON"
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
