{ writeShellApplication
, callPackage
, clamav
, coreutils
}:

writeShellApplication {
  name = "nixly-scan-file";
  runtimeInputs = [
    clamav
    coreutils
    (callPackage ./expand.nix { })
  ];
  text = builtins.readFile ./file.sh;
}
