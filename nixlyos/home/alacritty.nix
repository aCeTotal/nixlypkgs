{ pkgs, ... }:

{
    programs.alacritty.enable = true;

    home.packages = with pkgs; [
        nerd-fonts.jetbrains-mono
    ];


    home.file.".config/alacritty/alacritty.toml".text = ''

general.import = [
  "~/.config/alacritty/catppuccin-mocha.toml"
]

[env]
TERM = "xterm-256color"

[font]
size = 14.0

[font.bold]
family = "JetBrainsMono Nerd Font"
style = "Bold"

[font.bold_italic]
family = "JetBrainsMono Nerd Font"
style = "Bold Italic"

[font.italic]
family = "JetBrainsMono Nerd Font"
style = "Italic"

[font.normal]
family = "JetBrainsMono Nerd Font"
style = "Regular"

[window]
dynamic_padding = true
opacity = 0.75

[selection]
save_to_clipboard = true

# Make copy/paste bindings explicit (Ctrl+Shift+C/V)
[[keyboard.bindings]]
key = "C"
mods = "Control|Shift"
action = "Copy"

[[keyboard.bindings]]
key = "V"
mods = "Control|Shift"
action = "Paste"

# Paste primary selection with Shift+Insert (common on Linux)
[[keyboard.bindings]]
key = "Insert"
mods = "Shift"
action = "PasteSelection"
    '';


    home.file.".config/alacritty/catppuccin-mocha.toml".text = ''
[colors.primary]
background = "#1E1E2E"
foreground = "#CDD6F4"
dim_foreground = "#CDD6F4"
bright_foreground = "#CDD6F4"

[colors.cursor]
text = "#1E1E2E"
cursor = "#F5E0DC"

[colors.vi_mode_cursor]
text = "#1E1E2E"
cursor = "#B4BEFE"

[colors.search.matches]
foreground = "#1E1E2E"
background = "#A6ADC8"

[colors.search.focused_match]
foreground = "#1E1E2E"
background = "#A6E3A1"

[colors.footer_bar]
foreground = "#1E1E2E"
background = "#A6ADC8"

[colors.hints.start]
foreground = "#1E1E2E"
background = "#F9E2AF"

[colors.hints.end]
foreground = "#1E1E2E"
background = "#A6ADC8"

[colors.selection]
text = "#1E1E2E"
background = "#F5E0DC"

[colors.normal]
black = "#45475A"
red = "#F38BA8"
green = "#A6E3A1"
yellow = "#F9E2AF"
blue = "#89B4FA"
magenta = "#F5C2E7"
cyan = "#94E2D5"
white = "#BAC2DE"

[colors.bright]
black = "#585B70"
red = "#F38BA8"
green = "#A6E3A1"
yellow = "#F9E2AF"
blue = "#89B4FA"
magenta = "#F5C2E7"
cyan = "#94E2D5"
white = "#A6ADC8"

[colors.dim]
black = "#45475A"
red = "#F38BA8"
green = "#A6E3A1"
yellow = "#F9E2AF"
blue = "#89B4FA"
magenta = "#F5C2E7"
cyan = "#94E2D5"
white = "#BAC2DE"

[[colors.indexed_colors]]
index = 16
color = "#FAB387"

[[colors.indexed_colors]]
index = 17
color = "#F5E0DC"
    '';


}
