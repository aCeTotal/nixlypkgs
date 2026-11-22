{ writeShellApplication, coreutils, findutils, gawk, gnugrep, inotify-tools, procps, util-linux, vulkan-tools }:

# Steam shader replay and readahead.
writeShellApplication {
  name = "nixly-prewarm";
  runtimeInputs = [
    coreutils
    findutils
    gawk
    gnugrep
    inotify-tools
    procps
    util-linux
    vulkan-tools
  ];
  text = builtins.readFile ./nixly-prewarm;
}
