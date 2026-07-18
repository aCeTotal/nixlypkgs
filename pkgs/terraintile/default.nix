{ lib
, rustPlatform
, fetchFromGitHub
, pkg-config
, gdal
}:

rustPlatform.buildRustPackage rec {
  pname = "terraintile";
  version = "0-unstable-2026-07-18";

  src = fetchFromGitHub {
    owner = "aCeTotal";
    repo = "TerrainTile";
    rev = "b89e76ac9eac27c32a89d7b62d4268eea15678f6";
    hash = "sha256-H6qHUMlSNuUKYWnOwRatmSmC/WIJTMtk5edGa/q3Bj8=";
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
