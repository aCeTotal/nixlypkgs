{ ... }:

{
  # Colours from the wallpaper theme.
  programs.foot = {
    enable = true;
    settings.main.include = "~/.local/state/nixly-theme/foot.ini";
  };
}
