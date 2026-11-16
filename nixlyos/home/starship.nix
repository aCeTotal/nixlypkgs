{ pkgs, ... }:

{

    programs.starship = {
        enable = true;
        enableBashIntegration = true;
    };

    home.file.".config/starship.toml".text = ''

"$schema" = 'https://starship.rs/config-schema.json'

format = """
[](surface0)\
$os\
$username\
[](bg:sapphire fg:surface0)\
$directory\
[](fg:sapphire bg:blue)\
$git_branch\
$git_status\
[](fg:blue bg:lavender)\
$c\
$rust\
$golang\
$nodejs\
$php\
$java\
$kotlin\
$haskell\
$python\
[](fg:lavender bg:surface1)\
$docker_context\
[](fg:surface1 bg:surface1)\
$time\
[ ](fg:surface1)\
$line_break$character"""

palette = 'terminal'

[palettes.gruvbox_dark]
color_fg0 = '#fbf1c7'
color_bg1 = '#3c3836'
color_bg3 = '#665c54'
color_blue = '#458588'
color_aqua = '#689d6a'
color_green = '#98971a'
color_orange = '#d65d0e'
color_purple = '#b16286'
color_red = '#cc241d'
color_yellow = '#d79921'

# Follows the terminal palette.
[palettes.terminal]
text = "bright-white"
base = "black"
surface0 = "black"
surface1 = "black"
sapphire = "cyan"
lavender = "purple"

[os]
disabled = true
style = "bg:surface0 fg:text"

[os.symbols]
Windows = "󰍲"
Ubuntu = "󰕈"
SUSE = ""
Raspbian = "󰐿"
Mint = "󰣭"
Macos = ""
Manjaro = ""
Linux = "󰌽"
Gentoo = "󰣨"
Fedora = "󰣛"
Alpine = ""
Amazon = ""
Android = ""
Arch = "󰣇"
Artix = "󰣇"
CentOS = ""
Debian = "󰣚"
Redhat = "󱄛"
RedHatEnterprise = "󱄛"

[username]
show_always = true
style_user = "bg:surface0 fg:text"
style_root = "bg:surface0 fg:text"
format = '[ $user ]($style)'

[directory]
style = "fg:base bg:sapphire"
format = "[ $path ]($style)"
truncation_length = 3
truncation_symbol = "…/"

[directory.substitutions]
"Documents" = "󰈙 "
"Downloads" = " "
"Music" = "󰝚 "
"Pictures" = " "
"Developer" = "󰲋 "

[git_branch]
symbol = ""
style = "bg:blue"
format = '[[ $symbol $branch ](fg:base bg:blue)]($style)'

[git_status]
style = "bg:blue"
format = '[[($all_status$ahead_behind )](fg:base bg:blue)]($style)'

[nodejs]
symbol = ""
style = "bg:lavender"
format = '[[ $symbol( $version) ](fg:base bg:lavender)]($style)'

[c]
symbol = " "
style = "bg:lavender"
format = '[[ $symbol( $version) ](fg:base bg:lavender)]($style)'

[rust]
symbol = ""
style = "bg:lavender"
format = '[[ $symbol( $version) ](fg:base bg:lavender)]($style)'

[golang]
symbol = ""
style = "bg:lavender"
format = '[[ $symbol( $version) ](fg:base bg:lavender)]($style)'

[php]
symbol = ""
style = "bg:lavender"
format = '[[ $symbol( $version) ](fg:base bg:lavender)]($style)'

[java]
symbol = " "
style = "bg:lavender"
format = '[[ $symbol( $version) ](fg:base bg:lavender)]($style)'

[kotlin]
symbol = ""
style = "bg:lavender"
format = '[[ $symbol( $version) ](fg:base bg:lavender)]($style)'

[haskell]
symbol = ""
style = "bg:lavender"
format = '[[ $symbol( $version) ](fg:base bg:lavender)]($style)'

[python]
symbol = ""
style = "bg:lavender"
format = '[[ $symbol( $version) ](fg:base bg:lavender)]($style)'

[docker_context]
symbol = ""
style = "bg:surface1"
format = '[[ $symbol( $context) ](fg:text bg:surface1)]($style)'

[time]
disabled = true
time_format = "%R"
style = "bg:surface1"
format = '[[  $time ](fg:text bg:surface1)]($style)'

[line_break]
disabled = false

[character]
disabled = false
success_symbol = '[](bold fg:green)'
error_symbol = '[](bold fg:red)'
vimcmd_symbol = '[](bold fg:creen)'
vimcmd_replace_one_symbol = '[](bold fg:purple)'
vimcmd_replace_symbol = '[](bold fg:purple)'
vimcmd_visual_symbol = '[](bold fg:lavender)'
    '';

}
