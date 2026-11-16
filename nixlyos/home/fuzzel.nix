{ ... }:

{
  # Colours from the wallpaper theme.
  programs.fuzzel = {
    enable = true;
    settings.main.include = "~/.local/state/nixly-theme/fuzzel.ini";
  };
}
