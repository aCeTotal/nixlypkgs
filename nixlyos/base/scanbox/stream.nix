{ writeShellApplication
, callPackage
, runtimeShellPackage
, b3sum
, coreutils
, findutils
, libarchive
}:

writeShellApplication {
  name = "nixly-scan-stream";
  runtimeInputs = [
    b3sum
    (callPackage ./batches.nix { })
    (callPackage ./expand.nix { })
    coreutils
    findutils
    libarchive
  ];
  # Builtin stat/sleep avoid forks.
  runtimeEnv.BASH_LOADABLES_PATH = "${runtimeShellPackage}/lib/bash";
  text = builtins.readFile ./stream.sh;
}
