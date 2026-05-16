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
  version = "0-unstable-2025-05-16";

  src = fetchFromGitHub {
    owner = "aCeTotal";
    repo = "nixlymediaserver";
    rev = "d5e62b0319460bcaddde59e2a428e73195ff5272";
    hash = "sha256-EwLNKX7CwvpDVwB1W/qREgXVeVTDIenF0XSJ/gPrjzE=";
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
