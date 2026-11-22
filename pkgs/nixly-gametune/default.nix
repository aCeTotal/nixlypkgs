{ lib, writeShellScriptBin, coreutils, gnugrep, gawk, procps, util-linux, systemd, scx }:

# Root half of nixlytile's game mode.
writeShellScriptBin "nixly-gametune" ''
  export PATH=${lib.makeBinPath [
    coreutils
    gnugrep
    gawk
    procps
    util-linux
    systemd
    scx.rustscheds
  ]}:/run/current-system/sw/bin
  ${builtins.readFile ./nixly-gametune}
''
