{ config, lib, pkgs, ... }:

let
  # Neutral dark until the wallpaper theme lands.
  fuzzelSeed = pkgs.writeText "fuzzel-dark.ini" ''
    [colors]
    background=1d2024ff
    text=e1e2e8ff
    message=c4c6cfff
    prompt=c4c6cfff
    placeholder=8e9099ff
    input=e1e2e8ff
    match=a1cafdff
    selection=3a4857ff
    selection-text=d6e3f7ff
    selection-match=a1cafdff
    counter=8e9099ff
    border=44474eff
  '';
in
{
  # Include targets exist before nixlytile renders them.
  home.activation.nixlyTheme = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    d="${config.xdg.stateHome}/nixly-theme"
    run mkdir -p "$d"
    for f in foot.ini mpv.conf gtk.css alacritty.toml; do
      [ -e "$d/$f" ] || run touch "$d/$f"
    done
    [ -e "$d/fuzzel.ini" ] || run install -m644 ${fuzzelSeed} "$d/fuzzel.ini"
  '';
}
