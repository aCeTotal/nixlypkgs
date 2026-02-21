{ lib
, stdenv
, fetchFromGitHub
, pkg-config
, sqlite
, curl
, ffmpeg-headless
, cjson
}:

stdenv.mkDerivation rec {
  pname = "nixlymediaserver";
  version = "git";

  src = fetchFromGitHub {
    owner = "aCeTotal";
    repo = "nixlytile";
    rev = "66a80d0ed4efe1bbc024aaefbe1f876c25d0328f";
    hash = "sha256-pq6oetsvhjlnh7Wzqt48TnOzw9N5KW8CbFQQgkEv9tU=";
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
