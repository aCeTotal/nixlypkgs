{ lib, stdenv, fetchFromGitHub, meson, ninja, pkg-config, qt6 }:

let
  source = lib.importJSON ./source.json;
in
stdenv.mkDerivation {
  pname = "nixlykalk";
  inherit (source) version;

  src = fetchFromGitHub {
    owner = "aCeTotal";
    repo = "nixly_kalk";
    inherit (source) rev hash;
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
