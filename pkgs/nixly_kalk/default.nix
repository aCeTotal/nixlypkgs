{ lib, stdenv, fetchFromGitHub, meson, ninja, pkg-config, qt6 }:

stdenv.mkDerivation {
  pname = "nixlykalk";
  version = "0.0.1";

  src = fetchFromGitHub {
    owner = "aCeTotal";
    repo = "nixly_kalk";
    rev = "427c803777d39858ec08a8b275687bedb4d8d292";
    hash = "sha256-kPDQByqTNMuH920l7o0bmQkmrnvctruYUgmgOGd85pI=";
  };

  strictDeps = true;
  nativeBuildInputs = [ meson ninja pkg-config qt6.wrapQtAppsHook ];
  buildInputs = [ qt6.qtbase qt6.qtwayland ];

  mesonBuildType = "release";
  doCheck = true;

  postInstall = ''
    substituteInPlace $out/share/applications/nixlykalk.desktop \
      --replace-fail "Name=Calculator" "Name=Kalkulator"
  '';

  meta = {
    description = "Fast, modern calculator for NixlyOS";
    license = lib.licenses.gpl3Plus;
    platforms = lib.platforms.linux;
    mainProgram = "nixlykalk";
  };
}
