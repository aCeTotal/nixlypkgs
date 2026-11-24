{ nixlyUser, totalvimPkg, ... }:

let
  base = {
    home = {
      username = nixlyUser;
      homeDirectory = "/home/${nixlyUser}";
      stateVersion = "24.05";
      packages = [ totalvimPkg ];
      # PAM unlocks the login keyring.
      file.".local/share/keyrings/default".text = "login";
      sessionVariables = {
        EDITOR = "nvim";
        VISUAL = "nvim";
        BROWSER = "brave";
        TERMINAL = "alacritty";
      };
    };

    programs.bash.shellAliases = {
      "update" = "nixlyos-update";
      "nixly" = "cd $HOME/.local/nixlyos/";
    };

    dconf.settings = {
      "org/virt-manager/virt-manager/connections" = {
        autoconnect = [ "qemu:///system" ];
        uris = [ "qemu:///system" ];
      };
    };

    # Required by home-manager defaults.
    accounts.calendar.basePath = ".calendar";
    accounts.contact.basePath = ".contacts";

    programs.home-manager.enable = true;

    # Project compiler drives clangd.
    xdg.configFile."clangd/config.yaml".text = ''
      CompileFlags:
        Compiler: cc
    '';
  };

  bash =
    { pkgs, config, ... }:

    {
      home.packages = [ pkgs.eza ];

      programs = {
        bash = {
          enable = true;
          enableCompletion = true;

          shellAliases = {
            "z" = "zoxide";
            "pfo" = "cd /mnt/nfs/Bigdisk1/www/PFO";
            "work" = "cd /mnt/nfs/Bigdisk1/Work/painting";
            ".." = "cd ..";
            "ls" = "eza --long --all --header --group --git --icons --color=always";
          };

          # Commit everything and push.
          initExtra = ''
            push() {
                local msg
                if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
                    echo "push: not a git repo" >&2
                    return 1
                fi
                git add -A
                if git diff --cached --quiet; then
                    echo "push: nothing new to commit, pushing existing commits"
                    git push
                    return
                fi
                read -rep "commit> " msg || return 1
                if [ -z "$msg" ]; then
                    echo "push: empty message, aborted" >&2
                    git reset -q
                    return 1
                fi
                git commit -m "$msg" && git push
            }

            # Fast-forward a clean tree.
            pull() {
                if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
                    echo "pull: not a git repo" >&2
                    return 1
                fi
                if [ -n "$(git status --porcelain)" ]; then
                    echo "pull: uncommitted changes, aborted" >&2
                    return 1
                fi
                git fetch || return 1
                local behind
                behind=$(git rev-list --count HEAD..@{u} 2>/dev/null)
                if [ -z "$behind" ]; then
                    echo "pull: no upstream branch" >&2
                    return 1
                fi
                if [ "$behind" -eq 0 ]; then
                    echo "pull: already up to date"
                    return 0
                fi
                git pull --ff-only
            }

            # fetchFromGitHub fields for HEAD.
            hash() {
                local url owner_repo rev sha sri
                if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
                    echo "hash: not a git repo" >&2
                    return 1
                fi
                url=$(git remote get-url origin 2>/dev/null)
                if [ -z "$url" ]; then
                    echo "hash: no origin remote" >&2
                    return 1
                fi
                owner_repo=''${url#git@github.com:}
                owner_repo=''${owner_repo#https://github.com/}
                owner_repo=''${owner_repo%.git}
                rev=$(git rev-parse HEAD)
                if [ "$(git rev-parse @{u} 2>/dev/null)" != "$rev" ]; then
                    echo "hash: warning — HEAD differs from upstream, run push first" >&2
                fi
                echo "prefetching $owner_repo @ ''${rev:0:7} ..." >&2
                sha=$(nix-prefetch-url --unpack \
                    "https://github.com/$owner_repo/archive/$rev.tar.gz" 2>/dev/null)
                if [ -z "$sha" ]; then
                    echo "hash: prefetch failed (is $rev pushed to github?)" >&2
                    return 1
                fi
                sri=$(nix hash convert --hash-algo sha256 --to sri "$sha" 2>/dev/null \
                    || nix hash to-sri --type sha256 "$sha")
                echo "owner = \"''${owner_repo%%/*}\";"
                echo "repo = \"''${owner_repo##*/}\";"
                echo "rev = \"$rev\";"
                echo "hash = \"$sri\";"
            }

            # Silent fast-forward when possible.
            _auto_pull() {
                [ -n "$(git status --porcelain 2>/dev/null)" ] && return 0
                git fetch -q 2>/dev/null || return 0
                local behind
                behind=$(git rev-list --count HEAD..@{u} 2>/dev/null)
                [ -z "$behind" ] || [ "$behind" -eq 0 ] && return 0
                if git pull --ff-only -q >/dev/null 2>&1; then
                    echo "auto-pull: $behind new commit(s)"
                fi
            }

            # Once per entered repo.
            _git_enter_hook() {
                local top
                top=$(git rev-parse --show-toplevel 2>/dev/null)
                if [ -n "$top" ] && [ "$top" != "$_LAST_GIT_TOP" ]; then
                    _auto_pull
                fi
                _LAST_GIT_TOP=$top
            }
            PROMPT_COMMAND="_git_enter_hook''${PROMPT_COMMAND:+;$PROMPT_COMMAND}"

            # direnv loads only for nvim.
            nvim() {
                local top
                top=$(git rev-parse --show-toplevel 2>/dev/null)
                [ -n "$top" ] && _auto_pull
                if [ -n "$top" ] && [ -e "$top/flake.nix" ]; then
                    if [ ! -e "$top/.envrc" ]; then
                        printf 'use flake\n' > "$top/.envrc"
                        direnv allow "$top"
                    fi
                    direnv exec "$top" nvim "$@"
                else
                    command nvim "$@"
                fi
            }
          '';
        };
        direnv = {
          enable = true;
          # Only the nvim wrapper loads.
          enableBashIntegration = false;
          nix-direnv.enable = true;
          # Own repos never prompt.
          config.whitelist.prefix = [ "${config.home.homeDirectory}/git" ];
        };
      };
    }
  ;

  prompt =
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
  ;

  git =
    { pkgs, ... }:

    {

      home.packages = with pkgs; [
        libsecret
        git-lfs
      ];

      programs.git = {
        enable = true;
        package = pkgs.gitFull;
        signing.format = null;
        settings.user = {
          name = "aCeTotal";
          email = "lars.oksendal@gmail.com";
        };
      };

      programs.ssh = {
        enable = true;
        enableDefaultConfig = false;
        settings = {
          "*" = {
            Compression = true;
          };
          "github.com" = {
            IdentityFile = "~/.ssh/github";
          };
        };
      };
    }
  ;

  alacritty =
    { pkgs, ... }:

    {
      programs.alacritty.enable = true;

      home.packages = with pkgs; [
        nerd-fonts.jetbrains-mono
      ];


      home.file.".config/alacritty/alacritty.toml".text = ''

    general.import = [
      "~/.config/alacritty/catppuccin-mocha.toml",
      "~/.local/state/nixly-theme/alacritty.toml"
    ]

    [env]
    TERM = "xterm-256color"
    TERM_PROGRAM = "alacritty"

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

    # Ctrl+Shift+C/V copy and paste.
    [[keyboard.bindings]]
    key = "C"
    mods = "Control|Shift"
    action = "Copy"

    [[keyboard.bindings]]
    key = "V"
    mods = "Control|Shift"
    action = "Paste"

    # Shift+Insert pastes the selection.
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
      '';


    }
  ;

  # Colours follow the wallpaper.
  theme =
    { config, lib, pkgs, ... }:

    let
      # Neutral dark until themed.
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
      # Include targets exist before nixlytile.
      home.activation.nixlyTheme = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        d="${config.xdg.stateHome}/nixly-theme"
        run mkdir -p "$d"
        for f in foot.ini mpv.conf gtk.css alacritty.toml; do
          [ -e "$d/$f" ] || run touch "$d/$f"
        done
        [ -e "$d/fuzzel.ini" ] || run install -m644 ${fuzzelSeed} "$d/fuzzel.ini"
      '';

      programs.foot = {
        enable = true;
        settings.main.include = "~/.local/state/nixly-theme/foot.ini";
      };

      programs.fuzzel = {
        enable = true;
        settings.main.include = "~/.local/state/nixly-theme/fuzzel.ini";
      };

      programs.btop = {
        enable = true;
        settings = {
          color_theme = "nixly";
        };
      };
    };

  gtk =
    { config, pkgs, ... }:

    let
      adwDark = "${pkgs.adw-gtk3}/share/themes/adw-gtk3-dark";
      palette = "${config.xdg.stateHome}/nixly-theme/gtk.css";

      themeCss = gtk: extra: pkgs.writeText "nixly-${gtk}.css" ''
        @import url("file://${adwDark}/${gtk}/gtk.css");
        @import url("file://${palette}");
        ${extra}'';

      # adw-gtk3 hardcodes white here.
      gtk3Css = themeCss "gtk-3.0" ''
        button.suggested-action,
        button.suggested-action:hover,
        button.suggested-action:active,
        button.suggested-action:checked {
          color: @accent_fg_color;
        }
      '';
      # Replaces libadwaita's skipped providers.
      gtk4Css = themeCss "gtk-4.0" ''
        :root {
          --accent-bg-color: @accent_bg_color;
          --document-font-family: sans-serif;
          --monospace-font-family: monospace;
        }
      '';

      # Matugen flips gtk-theme between copies.
      theme = pkgs.linkFarm "nixly-gtk-theme" {
        "gtk-3.0/gtk.css" = gtk3Css;
        "gtk-3.0/gtk-dark.css" = gtk3Css;
        "gtk-4.0/gtk.css" = gtk4Css;
        "gtk-4.0/gtk-dark.css" = gtk4Css;
      };

      # libadwaita reloads only GTK_THEME.
      gtkTheme = "nixly-a:dark";
    in
    {
      home.pointerCursor = {
        enable = true;
        gtk.enable = true;
        package = pkgs.bibata-cursors;
        name = "Bibata-Modern-Ice";
        size = 21;
      };

      xdg.dataFile."themes/nixly-a".source = theme;
      xdg.dataFile."themes/nixly-b".source = theme;

      home.sessionVariables.GTK_THEME = gtkTheme;
      systemd.user.sessionVariables.GTK_THEME = gtkTheme;

      gtk = {
        enable = true;
        theme.name = "nixly-a";
        # GTK2 has no nixly theme.
        gtk2.theme = {
          name = "Adwaita-dark";
          package = pkgs.gnome-themes-extra;
        };
        gtk4.theme = null;
        iconTheme = {
          name = "Papirus-Dark";
          package = pkgs.papirus-icon-theme;
        };
        gtk3.extraConfig = {
          "gtk-enable-tooltips" = 1;
          "gtk-tooltip-timeout" = 10;
          "gtk-tooltip-browse-timeout" = 10;
          "gtk-tooltip-browse-mode-timeout" = 10;
        };
        gtk4.extraConfig = {
          "gtk-enable-tooltips" = 1;
          "gtk-tooltip-timeout" = 10;
          "gtk-tooltip-browse-timeout" = 10;
          "gtk-tooltip-browse-mode-timeout" = 10;
        };
      };
    }
  ;

  qt =
    { config, pkgs, ... }:

    {
      # Explicit packages skip Plasma closure.
      qt = {
        enable = true;
        platformTheme = {
          name = "kde";
          package = with pkgs.kdePackages; [ plasma-integration plasma-integration.qt5 ];
        };
        style = {
          name = "breeze";
          package = with pkgs.kdePackages; [ breeze breeze.qt5 ];
        };
      };

      # Breeze Dark fallback layer.
      home.packages = [
        (pkgs.runCommand "nixly-kdeglobals" { } ''
          mkdir -p $out/etc/xdg
          cp ${pkgs.kdePackages.breeze}/share/color-schemes/BreezeDark.colors $out/etc/xdg/kdeglobals
          chmod +w $out/etc/xdg/kdeglobals
          cat >> $out/etc/xdg/kdeglobals <<'EOF'

          [General]
          font=Noto Sans,10,-1,5,400,0,0,0,0,0,0,0,0,0,0,1
          menuFont=Noto Sans,10,-1,5,400,0,0,0,0,0,0,0,0,0,0,1
          toolBarFont=Noto Sans,10,-1,5,400,0,0,0,0,0,0,0,0,0,0,1
          smallestReadableFont=Noto Sans,8,-1,5,400,0,0,0,0,0,0,0,0,0,0,1
          fixed=JetBrainsMono Nerd Font,10,-1,5,400,0,0,0,0,0,0,0,0,0,0,1
          XftAntialias=true
          XftHintStyle=hintslight
          XftSubPixel=rgb

          [Icons]
          Theme=Papirus-Dark

          [KDE]
          widgetStyle=Breeze
          SingleClick=false
          AnimationDurationFactor=1

          [KFileDialog Settings]
          Allow Expansion=false
          Automatically select filename extension=true
          Breadcrumb Navigation=true
          Decoration position=2
          Show Full Path=false
          Show Inline Previews=true
          Show Preview=false
          Show Speedbar=true
          Show hidden files=false
          Sort by=Name
          Sort directories first=true
          Sort hidden files last=false
          Sort reversed=false
          Speedbar Width=148
          View Style=DetailTree
          EOF
        '')
      ];

      # Written by nixlytile's wallpaper theme.
      xdg.configFile."kdeglobals".source =
        config.lib.file.mkOutOfStoreSymlink "${config.xdg.stateHome}/nixly-theme/kdeglobals-colors";
    }
  ;
in
{
  home-manager.users.${nixlyUser}.imports = [
    base
    bash
    prompt
    git
    alacritty
    theme
    gtk
    qt
  ];
}
