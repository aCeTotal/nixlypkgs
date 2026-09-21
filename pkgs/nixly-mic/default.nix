{ lib, stdenv, pkg-config, pipewire }:

stdenv.mkDerivation {
  pname = "nixly-mic";
  version = "1.0";

  src = ./.;

  strictDeps = true;
  nativeBuildInputs = [ pkg-config ];
  buildInputs = [ pipewire ];

  buildPhase = ''
    runHook preBuild
    $CC -O2 -Wall -Wextra -o nixly-mic main.c pick.c route.c chain.c meterio.c meter.c control.c state.c \
      $(pkg-config --cflags --libs libpipewire-0.3) -lm
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 nixly-mic $out/bin/nixly-mic
    runHook postInstall
  '';

  meta = {
    description = "Automatic microphone gain and noise control for PipeWire";
    mainProgram = "nixly-mic";
    platforms = lib.platforms.linux;
  };
}
