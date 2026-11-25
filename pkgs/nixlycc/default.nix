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

let
  source = lib.importJSON ./source.json;
in
stdenv.mkDerivation {
  pname = "nixlycc";
  inherit (source) version;

  src = fetchFromGitHub {
    owner = "aCeTotal";
    repo = "nixlycc";
    inherit (source) rev hash;
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
