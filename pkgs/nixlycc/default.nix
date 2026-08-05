{ lib
, stdenv
, fetchFromGitHub
, meson
, ninja
, pkg-config
, qt6
, libdrm
, pam
, hwdata
}:

stdenv.mkDerivation {
  pname = "nixlycc";
  version = "0.2";

  src = fetchFromGitHub {
    owner = "aCeTotal";
    repo = "nixlycc";
    rev = "f27e2b95316ba22e351429fe46ee550afb41d1e7";
    hash = "sha256-yBmhzZZ48NIHJ2QHKMF3LtmJR3GtD2P4xYY0hz/8cTY=";
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
    qt6.qtsvg
    libdrm
    pam
    hwdata
  ];

  meta = with lib; {
    description = "NixlyCC - Control Center (settings/control panel) for NixlyOS";
    homepage = "https://github.com/aCeTotal/nixlycc";
    license = licenses.gpl3Plus;
    platforms = platforms.linux;
    mainProgram = "nixlycc";
  };
}
