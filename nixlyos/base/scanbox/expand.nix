{ writeShellApplication
, callPackage
, _7zz
, b3sum
, cabextract
, coreutils
, cpio
, dmg2img
, findutils
, gnugrep
, innoextract
, libarchive
, qemu-utils
, rpm
, squashfsTools
, util-linux
, wimlib
}:

writeShellApplication {
  name = "nixly-scan-expand";
  runtimeInputs = [
    _7zz
    b3sum
    (callPackage ./batches.nix { })
    cabextract
    coreutils
    cpio
    dmg2img
    findutils
    gnugrep
    innoextract
    libarchive
    qemu-utils
    rpm
    squashfsTools
    util-linux
    wimlib
  ];
  text = builtins.readFile ./expand.sh;
}
