{ lib, stdenvNoCC, python3, makeWrapper }:

stdenvNoCC.mkDerivation {
  pname = "meshy";
  version = "1.0";

  src = ./.;

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall
    install -Dm644 -t $out/share/meshy client.py meshy.py SKILL.md
    makeWrapper ${python3}/bin/python3 $out/bin/meshy --add-flags $out/share/meshy/meshy.py
    runHook postInstall
  '';

  meta = {
    description = "Meshy.ai CLI: text/image to 3D, rigging and animation as GLB";
    homepage = "https://docs.meshy.ai";
    platforms = lib.platforms.unix;
    mainProgram = "meshy";
  };
}
