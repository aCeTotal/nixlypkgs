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

let
  source = lib.importJSON ./source.json;
in
stdenv.mkDerivation rec {
  pname = "nixlymediaserver";
  inherit (source) version;

  src = fetchFromGitHub {
    owner = "aCeTotal";
    repo = "nixlymediaserver";
    inherit (source) rev hash;
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
