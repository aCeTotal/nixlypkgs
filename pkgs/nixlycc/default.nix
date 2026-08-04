{ lib
, stdenv
, fetchFromGitHub
, meson
, ninja
, pkg-config
, qt6
, libdrm
}:

stdenv.mkDerivation {
  pname = "nixlycc";
  version = "0.2";

  src = fetchFromGitHub {
    owner = "aCeTotal";
    repo = "nixlycc";
    rev = "8b84bf7062139669354468e95ccf7b30ce2b1e26";
    hash = "sha256-njMRkdVGD0zupv+TqUD1qGGd+Fr4HL5Xyb9puEvCp/c=";
  };

  nativeBuildInputs = [
    meson
    ninja
    pkg-config
    qt6.wrapQtAppsHook
  ];

  buildInputs = [
    qt6.qtbase
    qt6.qtwayland
    libdrm
  ];

  meta = with lib; {
    description = "NixlyCC - Control Center (settings/control panel) for NixlyOS";
    homepage = "https://github.com/aCeTotal/nixlycc";
    license = licenses.gpl3Plus;
    platforms = platforms.linux;
    mainProgram = "nixlycc";
  };
}
