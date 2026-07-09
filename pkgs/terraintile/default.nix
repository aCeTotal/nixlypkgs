{ lib
, rustPlatform
, fetchFromGitHub
, pkg-config
, gdal
}:

rustPlatform.buildRustPackage rec {
  pname = "terraintile";
  version = "0-unstable-2026-07-09";

  src = fetchFromGitHub {
    owner = "aCeTotal";
    repo = "TerrainTile";
    rev = "00710f4e150ba258118b6c995bbcf40fad0f34f7";
    hash = "sha256-stFMgcs1tGukOzAaR6ABHilCN3yiFMYSL1uK/lPzpns=";
  };

  cargoLock.lockFile = "${src}/Cargo.lock";

  nativeBuildInputs = [
    pkg-config
    rustPlatform.bindgenHook
  ];

  buildInputs = [ gdal ];

  meta = with lib; {
    description = "Headless terrain pipeline with web UI and in-browser 3D viewer";
    homepage = "https://github.com/aCeTotal/TerrainTile";
    license = licenses.gpl3Plus;
    platforms = platforms.linux;
    mainProgram = "terraintile";
  };
}
