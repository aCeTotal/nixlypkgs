{ lib
, stdenv
, fetchFromGitHub
, pkg-config
, sqlite
, curl
, ffmpeg-headless
, cjson
, libzip
, libarchive
}:

stdenv.mkDerivation rec {
  pname = "nixlymediaserver";
  version = "git";

  src = fetchFromGitHub {
    owner = "aCeTotal";
    repo = "nixlytile";
    rev = "54a9d3d66ff7bed623f9cb5dbe452f511ae8a50d";
    hash = "sha256-5ASliqfXZ4/ISLxp/Ytd07g2zqlbQoXx+45p4yb9ooQ=";
  };

  sourceRoot = "${src.name}/Server";

  nativeBuildInputs = [
    pkg-config
  ];

  buildInputs = [
    sqlite
    curl
    ffmpeg-headless
    cjson
    libzip
    libarchive
  ];

  makeFlags = [
    "CC=${stdenv.cc.targetPrefix}cc"
  ];

  preBuild = ''
    # Repo has pre-compiled .o files committed; force a clean rebuild
    make clean
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    cp nixly-server $out/bin/

    mkdir -p $out/share/nixlymediaserver
    cp ${src}/Server/config.conf.example $out/share/nixlymediaserver/ 2>/dev/null || true

    runHook postInstall
  '';

  meta = with lib; {
    description = "Nixly Media Server - Lossless streaming server for movies and TV shows";
    homepage = "https://github.com/aCeTotal/nixlytile";
    license = licenses.gpl3Plus;
    platforms = platforms.linux;
    mainProgram = "nixly-server";
  };
}
