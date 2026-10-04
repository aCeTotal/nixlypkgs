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
    rev = "ed8cdd80b5c8c2ac6ee3d60021d05af2eddf22bb";
    hash = "sha256-ygEoTgVPsgcY8xfBc5KMIwsfhdPnYmvlVgpmp4taqgY=";
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
