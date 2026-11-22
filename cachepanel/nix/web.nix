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
  npmDepsHash = "sha256-weW2h5YH3EQSeZY8ZWmg5z1tFgK6YWcRlgI1J+cIeks=";

  installPhase = ''
    runHook preInstall
    cp -r dist $out
    runHook postInstall
  '';
}
