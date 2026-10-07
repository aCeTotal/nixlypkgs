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
    rev = "da0210afeaf51aec493680867a1b1e82954e44c7";
    hash = "sha256-Y4KluXkKPaTMjgNUVMGjB3apXmkz0VRjYx7HO/ZS9ro=";
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
