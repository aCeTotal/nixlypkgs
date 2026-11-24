# Leser kernelversjonen ut av kildetreets Makefile ved eval-tid.
{ lib, src }:
let
  head = builtins.substring 0 200 (builtins.readFile "${src}/Makefile");
  lines = lib.splitString "\n" head;
  val =
    key:
    let
      line = lib.lists.findFirst (l: lib.hasPrefix "${key} =" l) (throw
        "fant ikke '${key}' i kernel-Makefile"
      ) lines;
    in
    lib.strings.trim (lib.removePrefix "${key} =" line);
in
"${val "VERSION"}.${val "PATCHLEVEL"}.${val "SUBLEVEL"}${val "EXTRAVERSION"}"
