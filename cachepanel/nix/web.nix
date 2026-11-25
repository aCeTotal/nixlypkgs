{ lib, buildNpmPackage, nodejs_24 }:

buildNpmPackage {
  pname = "nixly-panel-web";
  version = "0.1.0";
  src = lib.fileset.toSource {
    root = ../web;
    fileset = lib.fileset.difference ../web (lib.fileset.unions [
      (lib.fileset.maybeMissing ../web/node_modules)
      (lib.fileset.maybeMissing ../web/dist)
    ]);
  };
  nodejs = nodejs_24;
  npmDepsHash = "sha256-mzXi2i/OEoBs/DJIxFhH9fs1Tfyga4u92PlD6ek7klI=";

  installPhase = ''
    runHook preInstall
    cp -r dist $out
    runHook postInstall
  '';
}
