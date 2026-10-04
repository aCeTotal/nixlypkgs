{ lib, stdenv, ladspa-header }:

stdenv.mkDerivation {
  pname = "nixly-gate";
  version = "1.0";

  src = ./.;

  strictDeps = true;
  buildInputs = [ ladspa-header ];

  buildPhase = ''
    runHook preBuild
    $CC -O2 -Wall -Wextra -shared -fPIC -o nixly_gate.so gate.c
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 nixly_gate.so $out/lib/ladspa/nixly_gate.so
    runHook postInstall
  '';

  meta = {
    description = "Shared-memory microphone gate for push-to-talk";
    platforms = lib.platforms.linux;
  };
}
