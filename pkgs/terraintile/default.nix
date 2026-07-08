{ lib
, rustPlatform
, fetchFromGitHub
, pkg-config
, gdal
}:

rustPlatform.buildRustPackage rec {
  pname = "terraintile";
  version = "0-unstable-2026-07-08";

  src = fetchFromGitHub {
    owner = "aCeTotal";
    repo = "TerrainTile";
    rev = "14cd33c11c1ba1204a84e79927d4494cef06b5de";
    hash = "sha256-cM3FwQc2dvbkOyw6RRnHqLiIq3PzzUkyACkhDlwmb24=";
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
