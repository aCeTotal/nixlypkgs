{ lib, stdenv, pkg-config, systemd, libx11, libxtst, libxi }:

stdenv.mkDerivation {
  pname = "discord-keybridge";
  version = "1.0";

  src = ./.;

  strictDeps = true;
  nativeBuildInputs = [ pkg-config ];
  buildInputs = [ systemd libx11 libxtst libxi ];

  buildPhase = ''
    runHook preBuild
    $CC -O2 -Wall -Wextra -o discord-keybridge main.c xkeys.c \
      $(pkg-config --cflags --libs libsystemd x11 xtst xi)
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 discord-keybridge $out/bin/discord-keybridge
    runHook postInstall
  '';

  meta = {
    description = "Replays portal global shortcuts as X11 keys for Discord";
    mainProgram = "discord-keybridge";
    platforms = lib.platforms.linux;
  };
}
