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
    rev = "a15bfa1353c2d90f56742aa107ac39b1160e52fa";
    hash = "sha256-nhwdTMg0N2ZF4qhKI57pk4eNFkzPvhhw+opDDvpCGwM=";
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
