{ writeShellApplication
, clamav
, coreutils
}:

writeShellApplication {
  name = "nixly-scan-batches";
  runtimeInputs = [
    clamav
    coreutils
  ];
  text = builtins.readFile ./batches.sh;
}
