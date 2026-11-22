# Builds Arch PKGBUILDs in Nix.
{
  lib,
  stdenv,
  stdenvNoCC,
  makeSetupHook,
  writeShellScriptBin,
  libarchive,
  perl,
  zstd,
  fakeroot,
  autoconf,
  automake,
  libtool,
  m4,
  pkg-config,
  bison,
  flex,
  gettext,
  texinfo,
  which,
  file,
  rustPlatform,
  go,
  cacert,
  fetchNpmDeps,
  nodejs,
  python3Packages,
}:

let
  makepkgHook = makeSetupHook {
    name = "makepkg-hook";
    propagatedBuildInputs = [ libarchive perl zstd fakeroot ];
  } ./makepkg-hook.sh;

  # Arch's meson defaults, store prefix.
  archMeson = writeShellScriptBin "arch-meson" ''
    exec meson setup --prefix "$out" --libexecdir lib --sbindir bin --buildtype plain \
      --auto-features auto --wrap-mode nodownload -D b_pie=true -D python.bytecompile=1 "$@"
  '';

  # Store files carry no capabilities.
  noSetcap = writeShellScriptBin "setcap" ''
    echo "makepkg: ignoring setcap $*"
  '';

  # What Arch assumes from base-devel.
  baseDevel = [ autoconf automake libtool m4 pkg-config bison flex gettext texinfo which file ];

  goModulesOf = { pname, version, src, hash }: stdenvNoCC.mkDerivation {
    name = "${pname}-${version}-go-modules";
    inherit src;
    nativeBuildInputs = [ go cacert ];
    impureEnvVars = lib.fetchers.proxyImpureEnvVars ++ [ "GOPROXY" ];
    dontConfigure = true;
    buildPhase = ''
      export GOPATH=$TMPDIR/go GOCACHE=$TMPDIR/go-cache GOTOOLCHAIN=local
      for depth in 1 2 3 4; do
        mod=$(find . -maxdepth $depth -name go.mod -not -path "*/vendor/*" -not -path "*/testdata/*" | head -1)
        if [ -n "$mod" ]; then break; fi
      done
      cd "$(dirname "$mod")"
      go mod download
    '';
    installPhase = ''
      rm -rf "$GOPATH/pkg/mod/cache/download/sumdb"
      cp -r "$GOPATH/pkg/mod/cache/download" $out
    '';
    dontFixup = true;
    outputHashMode = "recursive";
    outputHash = hash;
  };
in
lib.extendMkDerivation {
  constructDrv = stdenv.mkDerivation;
  excludeDrvArgNames = [ "cargoHash" "goHash" "npmHash" "depends" "pythonDepends" ];
  extendDrvArgs =
    finalAttrs:
    {
      pkgbuild,
      srcs,
      split ? null,
      cargoHash ? null,
      goHash ? null,
      npmHash ? null,
      depends ? [ ],
      pythonDepends ? [ ],
      nativeBuildInputs ? [ ],
      buildInputs ? [ ],
      ...
    }@args:
    let
      main = builtins.head srcs;
    in
    {
      inherit pkgbuild split;
      CARCH = stdenv.hostPlatform.parsed.cpu.name;
      CHOST = stdenv.hostPlatform.config;
      glibcVersion = stdenv.cc.libc.version;
      nativeBuildInputs = [ makepkgHook archMeson noSetcap ] ++ baseDevel
        ++ lib.optional (pythonDepends != [ ]) python3Packages.wrapPython
        ++ nativeBuildInputs;
      buildInputs = depends ++ buildInputs;
      propagatedUserEnvPkgs = depends;
      pythonPath = pythonDepends;

      cargoDeps = lib.mapNullable (hash: rustPlatform.fetchCargoVendor {
        inherit (finalAttrs) pname version;
        src = main;
        inherit hash;
      }) cargoHash;
      goModules = lib.mapNullable (hash: goModulesOf {
        inherit (finalAttrs) pname version;
        src = main;
        inherit hash;
      }) goHash;
      npmDeps = lib.mapNullable (hash: fetchNpmDeps {
        name = "${finalAttrs.pname}-${finalAttrs.version}-npm-deps";
        src = main;
        inherit hash;
      }) npmHash;
      nodeDir = lib.optionalString (npmHash != null) nodejs;

      unpackPhase = "makepkgUnpackPhase";
      configurePhase = "makepkgConfigurePhase";
      buildPhase = "makepkgBuildPhase";
      installPhase = "makepkgInstallPhase";
      postFixup = (args.postFixup or "") + lib.optionalString (pythonDepends != [ ]) "wrapPythonPrograms";
    };
}
