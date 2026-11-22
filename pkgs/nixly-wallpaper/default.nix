{ runCommand }:

# Default NixlyOS wallpaper.
runCommand "nixly-wallpaper" { } ''
  install -Dm644 ${./mountains.jpg} $out/share/wallpapers/mountains.jpg
''
