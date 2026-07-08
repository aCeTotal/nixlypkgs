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
    rev = "c859327f6c6ddba6e19025de64f309b3ebdebaea";
    hash = "sha256-JOAmmkLSDIOwJHCy7zfvpwyQ2wlzHSI1KobcPnz6WKc=";
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
