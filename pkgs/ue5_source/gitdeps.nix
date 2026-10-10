{
  lib,
  runCommand,
  linkFarm,
  fetchurl,
  python3,
  manifest,
}:

# Epic CDN packs, one store path each.
prefixes:

let
  index = lib.importJSON (
    runCommand "ue5-gitdeps.json" { nativeBuildInputs = [ python3 ]; } ''
      python3 ${./gitdeps.py} packs ${manifest} ${lib.escapeShellArgs prefixes} > "$out"
    ''
  );

  fetchPack =
    { hash, remote }:
    {
      name = hash;
      path = fetchurl {
        name = "ue5-pack-${hash}";
        url = "${index.base}/${remote}/${hash}";
        sha1 = hash;
        downloadToTemp = true;
        postFetch = ''gunzip -c "$downloadedFile" > "$out"'';
      };
    };
in
linkFarm "ue5-gitdeps" (map fetchPack index.packs)
