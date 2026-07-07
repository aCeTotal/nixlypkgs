{ lib
, rustPlatform
, fetchFromGitHub
, pkg-config
, gdal
}:

rustPlatform.buildRustPackage rec {
  pname = "terraintile";
  version = "0-unstable-2026-07-07";

  src = fetchFromGitHub {
    owner = "aCeTotal";
    repo = "TerrainTile";
    rev = "fcc047c35aee0daef0f89451478a2049e72725ca";
    hash = "sha256-h2nO1kEp5jd6l9XHt+PXCrKE3iwX6BsFdC+Qt96vF5o=";
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
