{ writeShellApplication
, _7zz
, cabextract
, clamav
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
    cabextract
    clamav
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
