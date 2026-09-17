{ ... }:

{
  # Workspace for unpacked containers: root only, and outside every path
  # the download gate watches so expanding never re-enters the scanner.
  systemd.tmpfiles.rules = [
    "d /var/lib/nixly-scanbox 0700 root root -"
  ];
}
