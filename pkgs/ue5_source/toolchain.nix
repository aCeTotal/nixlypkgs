{
  lib,
  fetchurl,
  autoPatchelfHook,
  stdenv,
  zlib,
  version,
  hash,
}:

# Epic clang, host tools patched.

stdenv.mkDerivation {
  pname = "ue5-linux-toolchain";
  inherit version;

  src = fetchurl {
    url = "https://cdn.unrealengine.com/Toolchain_Linux/native-linux-${version}.tar.gz";
    inherit hash;
  };

  nativeBuildInputs = [ autoPatchelfHook ];
  buildInputs = [
    stdenv.cc.cc.lib
    zlib
  ];

  # Sysroot stays as Epic ships.
  dontFixup = true;

  installPhase = ''
    runHook preInstall
    mkdir -p "$out"
    cp -r ToolchainVersion.txt x86_64-unknown-linux-gnu "$out/"
    autoPatchelf "$out/x86_64-unknown-linux-gnu/bin"
    runHook postInstall
  '';

  meta = {
    description = "Unreal Engine Linux clang toolchain ${version}";
    homepage = "https://dev.epicgames.com/documentation/en-us/unreal-engine/linux-development-requirements-for-unreal-engine";
    license = lib.licenses.ncsa;
    platforms = [ "x86_64-linux" ];
  };
}
