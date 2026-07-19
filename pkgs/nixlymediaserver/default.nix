{ lib
, stdenv
, fetchFromGitHub
, makeWrapper
, pkg-config
, sqlite
, curl
, ffmpeg-headless
, cjson
, xdg-utils
}:

stdenv.mkDerivation rec {
  pname = "nixlymediaserver";
  version = "0-unstable-2026-07-19";

  src = fetchFromGitHub {
    owner = "aCeTotal";
    repo = "nixlymediaserver";
    rev = "08ccf48d5178ec97e03b87388bbd6da3211977b8";
    hash = "sha256-UAAr1luaSK0aSQ4CU+q3Ce+QHT3tBW5AAZjRMfWRrr8=";
  };

  nativeBuildInputs = [
    pkg-config
    makeWrapper
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
    # Repo ships pre-compiled .o files; force a clean rebuild.
    make clean
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    cp nixly-server $out/bin/
    wrapProgram $out/bin/nixly-server \
      --prefix PATH : ${lib.makeBinPath [ xdg-utils ]}

    runHook postInstall
  '';

  meta = with lib; {
    description = "Lossless streaming media server with TMDB scraping, downloader, IP gate and live admin UI";
    homepage = "https://github.com/aCeTotal/nixlymediaserver";
    license = licenses.gpl3Plus;
    platforms = platforms.linux;
    mainProgram = "nixly-server";
  };
}
