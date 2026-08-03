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
    rev = "751383130f6eb64eff2c17ae3a004b34c2a9a980";
    hash = "sha256-X9DCEpBTcJVHgsldVaoZXVY7sIA86hVwuykKhM1G56w=";
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
