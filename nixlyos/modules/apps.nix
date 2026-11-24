{ lib, ... }:

let
  # Drops packages the platform lacks.
  everyday = {
    home-manager.sharedModules = [
      ({ pkgs, ... }: {
        home.packages = builtins.filter
          (lib.meta.availableOn pkgs.stdenv.hostPlatform)
          (with pkgs; [
            brave
            discord
            google-chrome
            libreoffice-fresh
            nixlymedia
            pavucontrol
            spotify
            teams-for-linux
            vlc
          ]);
      })
    ];
  };

  # Browsing plus Shields only.
  browser = {
    environment.etc."brave/policies/managed/lean.json".text = builtins.toJSON {
      BackgroundModeEnabled = false;
      DefaultBrowserSettingEnabled = false;
      MetricsReportingEnabled = false;
      PromotionsEnabled = false;
      BraveAIChatEnabled = false;
      BraveLocalAIEnabled = false;
      BraveNewsDisabled = true;
      BraveP3AEnabled = false;
      BravePlaylistEnabled = false;
      BraveRewardsDisabled = true;
      BraveSpeedreaderEnabled = false;
      BraveStatsPingEnabled = false;
      BraveTalkDisabled = true;
      BraveVPNDisabled = true;
      BraveWalletDisabled = true;
      BraveWaybackMachineEnabled = false;
      BraveWebDiscoveryEnabled = false;
      TorDisabled = true;
      TranslateEnabled = false;
      HardwareAccelerationModeEnabled = true;
      # Blank tab on start.
      RestoreOnStartup = 5;
      DefaultSearchProviderEnabled = true;
      DefaultSearchProviderName = "Google";
      DefaultSearchProviderKeyword = "google.com";
      DefaultSearchProviderSearchURL = "https://www.google.com/search?q={searchTerms}";
      DefaultSearchProviderSuggestURL = "https://www.google.com/complete/search?client=chrome&q={searchTerms}";
    };

    home-manager.sharedModules = [
      {
        xdg.mimeApps = {
          enable = true;
          defaultApplications = {
            "text/html" = [ "brave-browser.desktop" ];
            "x-scheme-handler/http" = [ "brave-browser.desktop" ];
            "x-scheme-handler/https" = [ "brave-browser.desktop" ];
          };
        };
      }
    ];
  };

  feeds =
    { pkgs, ... }:

    {
      config.home-manager.sharedModules = [
        {
          programs.newsboat = {
            enable = true;

            extraConfig = ''
              # Catppuccin Mocha colours
              color background          color236  default
              color listnormal          color7    default
              color listnormal_unread   color4    default   bold
              color listfocus           color0    color4
              color listfocus_unread    color0    color4    bold
              color info                color0    color5    bold
              color article             color7    default
              color hint-key            color3    default   bold
              color hint-keys-delimiter color8    default
              color hint-separator      color8    default
              color title               color5    default   bold
              color end-of-text-marker  color8    default

              # Highlight for article content
              highlight article "^Feed:.*"        color5  default bold
              highlight article "^Title:.*"       color4  default bold
              highlight article "^Author:.*"      color3  default
              highlight article "^Date:.*"        color6  default
              highlight article "^Link:.*"        color6  default underline
              highlight article "\\[image\\ [0-9]+.*\\]" color8 default
              highlight article "\\[link\\ [0-9]+\\]"    color6 default underline
              highlight article "https?://[^ ]+"  color6  default underline

              # Highlight in the feed list
              highlight feedlist "linux"           color2  default bold
              highlight feedlist "valve|steam|proton" color4 default bold
              highlight feedlist "tech"            color5  default bold

              # Formatting
              feedlist-format     "%?T?%-14T ?%t %> %U/%c "
              articlelist-format  "%D  %?T?%-12T  ?%t %> %L"
              datetime-format     "%d/%m"
              feedlist-title-format "  Feeds (%u uleste, %t totalt)%?T? - %T?"
              articlelist-title-format "  %T (%u uleste)%?F? - %F?"
              searchresult-title-format "  Sok - %s (%u uleste)"
              filebrowser-title-format "%?O?Lagre fil:&Apne fil:? %f"
              itemview-title-format "  %T"

              text-width 90

              # Behaviour
              auto-reload yes
              reload-time 30
              reload-threads 4
              prepopulate-query-feeds yes
              show-read-feeds yes
              show-read-articles no
              confirm-mark-feed-read no
              cleanup-on-quit yes
              max-items 200

              # Browser
              browser "xdg-open %u"
              macro o set browser "xdg-open %u" ; open-in-browser ; set browser "xdg-open %u"
              macro v set browser "mpv %u" ; open-in-browser ; set browser "xdg-open %u"

              # Vim keybindings
              bind-key j down
              bind-key k up
              bind-key J next-feed articlelist
              bind-key K prev-feed articlelist
              bind-key g home
              bind-key G end
              bind-key l open
              bind-key h quit
              bind-key n next-unread
              bind-key N prev-unread
              bind-key u show-urls
              bind-key SPACE toggle-article-read
              bind-key ^D pagedown
              bind-key ^U pageup
              bind-key d toggle-show-read-feeds
              bind-key D delete-article
              bind-key ^R reload-all
            '';

            urls = [
              # Linux news
              { url = "https://www.phoronix.com/rss.php"; tags = [ "linux" "hardware" ]; title = "Phoronix"; }
              { url = "https://lwn.net/headlines/rss"; tags = [ "linux" "kernel" ]; title = "LWN.net"; }
              { url = "https://www.omgubuntu.co.uk/feed"; tags = [ "linux" "ubuntu" ]; title = "OMG! Ubuntu"; }
              { url = "https://www.gamingonlinux.com/article_rss.php"; tags = [ "linux" "gaming" ]; title = "GamingOnLinux"; }
              { url = "https://linuxgamingcentral.com/index.xml"; tags = [ "linux" "gaming" ]; title = "Linux Gaming Central"; }
              { url = "https://itsfoss.com/feed/"; tags = [ "linux" ]; title = "It's FOSS"; }
              { url = "https://9to5linux.com/feed"; tags = [ "linux" ]; title = "9to5Linux"; }
              { url = "https://www.linuxtoday.com/feed/"; tags = [ "linux" ]; title = "Linux Today"; }
              { url = "https://tuxphones.com/rss/"; tags = [ "linux" "mobile" ]; title = "TuxPhones"; }
              { url = "https://thisweek.gnome.org/index.xml"; tags = [ "linux" "gnome" ]; title = "This Week in GNOME"; }
              { url = "https://pointieststick.com/feed/"; tags = [ "linux" "kde" ]; title = "This Week in KDE (Nate)"; }
              { url = "https://blog.torproject.org/feed/"; tags = [ "linux" "privacy" ]; title = "Tor Project"; }
              { url = "https://fedoramagazine.org/feed/"; tags = [ "linux" "fedora" ]; title = "Fedora Magazine"; }
              { url = "https://archlinux.org/feeds/news/"; tags = [ "linux" "arch" ]; title = "Arch Linux News"; }
              { url = "https://weekly.nixos.org/feeds/all.rss.xml"; tags = [ "linux" "nix" ]; title = "NixOS Weekly"; }
              { url = "https://discourse.nixos.org/c/announcements/8.rss"; tags = [ "linux" "nix" ]; title = "NixOS Announcements"; }
              { url = "https://planet.kernel.org/rss20.xml"; tags = [ "linux" "kernel" ]; title = "Planet Kernel"; }

              # Valve, Steam and Proton
              { url = "https://store.steampowered.com/feeds/news/app/593110"; tags = [ "valve" "steam" ]; title = "Steam Deck News"; }
              { url = "https://store.steampowered.com/feeds/news/app/1493710"; tags = [ "valve" "proton" ]; title = "Proton Experimental"; }
              { url = "https://store.steampowered.com/feeds/news/app/2180100"; tags = [ "valve" "proton" ]; title = "Proton Hotfix"; }
              { url = "https://store.steampowered.com/feeds/news/app/2805730"; tags = [ "valve" "deadlock" ]; title = "Deadlock"; }
              { url = "https://store.steampowered.com/feeds/news/app/730"; tags = [ "valve" "cs2" ]; title = "Counter-Strike 2"; }
              { url = "https://store.steampowered.com/feeds/news/app/570"; tags = [ "valve" "dota2" ]; title = "Dota 2"; }
              { url = "https://www.valvesoftware.com/en/blog?feed=rss"; tags = [ "valve" ]; title = "Valve Blog"; }
              { url = "https://boilingsteam.com/feed/"; tags = [ "valve" "linux" "gaming" ]; title = "Boiling Steam"; }

              # Tech news
              { url = "https://arstechnica.com/feed/"; tags = [ "tech" ]; title = "Ars Technica"; }
              { url = "https://www.theverge.com/rss/index.xml"; tags = [ "tech" ]; title = "The Verge"; }
              { url = "https://techcrunch.com/feed/"; tags = [ "tech" ]; title = "TechCrunch"; }
              { url = "https://www.anandtech.com/rss/"; tags = [ "tech" "hardware" ]; title = "AnandTech"; }
              { url = "https://feeds.arstechnica.com/arstechnica/gadgets"; tags = [ "tech" "hardware" ]; title = "Ars Technica Hardware"; }
              { url = "https://www.tomshardware.com/feeds/all"; tags = [ "tech" "hardware" ]; title = "Tom's Hardware"; }
              { url = "https://hackaday.com/feed/"; tags = [ "tech" "diy" ]; title = "Hackaday"; }
              { url = "https://news.ycombinator.com/rss"; tags = [ "tech" ]; title = "Hacker News"; }
              { url = "https://lobste.rs/rss"; tags = [ "tech" "programming" ]; title = "Lobsters"; }
              { url = "https://www.wired.com/feed/rss"; tags = [ "tech" ]; title = "Wired"; }
              { url = "https://www.bleepingcomputer.com/feed/"; tags = [ "tech" "security" ]; title = "BleepingComputer"; }
              { url = "https://krebsonsecurity.com/feed/"; tags = [ "tech" "security" ]; title = "Krebs on Security"; }
              { url = "https://www.schneier.com/feed/atom/"; tags = [ "tech" "security" ]; title = "Schneier on Security"; }
              { url = "https://www.servethehome.com/feed/"; tags = [ "tech" "server" ]; title = "ServeTheHome"; }
              { url = "https://selfhosted.show/rss"; tags = [ "tech" "selfhost" ]; title = "Self-Hosted Podcast"; }
              { url = "https://blog.cloudflare.com/rss/"; tags = [ "tech" "web" ]; title = "Cloudflare Blog"; }

              # GPUs
              { url = "https://videocardz.com/feed"; tags = [ "tech" "gpu" ]; title = "VideoCardz"; }
              { url = "https://www.nvidia.com/en-us/drivers/unix/feed.xml"; tags = [ "tech" "gpu" "nvidia" ]; title = "NVIDIA Unix Drivers"; }

              # Open source
              { url = "https://github.blog/feed/"; tags = [ "tech" "foss" ]; title = "GitHub Blog"; }
              { url = "https://www.opensourceforu.com/feed/"; tags = [ "tech" "foss" ]; title = "Open Source For You"; }
            ];
          };
        }
      ];
    }
  ;

  textBrowser =
    { ... }:

    {
      config.home-manager.sharedModules = [
        ({ pkgs, ... }: {
          home.packages = with pkgs; [ w3m ];

          # w3m ignores XDG.
          home.file.".w3m/config".text = ''
            # Charset
            display_charset UTF-8
            document_charset UTF-8
            system_charset UTF-8
            auto_detect 2

            # Display
            color 1
            ansi_color 1
            use_mouse 1
            clear_buffer 1
            decode_cte 1
            fold_textarea 1
            display_image 0
            pseudo_inlines 1
            tabstop 4
            indent_incr 2

            # Navigation
            nextpage_topline 1
            label_topline 1
            emacs_like_lineedit 1
            vi_prec_num 1

            # Cookies / cache
            use_cookie 1
            accept_cookie 1
            accept_bad_cookie 0
            cookie_avoid_wrong_number_of_dots ""
            show_cookie 0

            # Tabs
            open_tab_blank 1
            open_tab_dl_list 1
            close_tab_back 1

            # Forms
            confirm_qq 0
            target_self 1

            # Downloads land in PWD.
            download_dir .
            decode_cte 1
            auto_uncompress 1

            # Editor / pager
            editor nvim

            # M: open, wget, copy.
            extbrowser  sh -c 'xdg-open "%s" &'
            extbrowser2 sh -c 'wget --content-disposition -- "%s"'
            extbrowser3 sh -c 'echo -n "%s" | wl-copy'
            mailto_options 0

            # SSL
            ssl_verify_server 1
            ssl_ca_file /etc/ssl/certs/ca-certificates.crt

            # Search
            case_sensitive 0
            wrap_search 1
          '';

          # Vim-like keymap.
          home.file.".w3m/keymap".text = ''
            # Movement
            keymap  j         MOVE_DOWN
            keymap  k         MOVE_UP
            keymap  h         MOVE_LEFT
            keymap  l         MOVE_RIGHT
            keymap  g         BEGIN
            keymap  G         END
            keymap  C-f       NEXT_PAGE
            keymap  C-b       PREV_PAGE
            keymap  C-d       NEXT_HALF_PAGE
            keymap  C-u       PREV_HALF_PAGE
            keymap  H         LINE_BEGIN
            keymap  L         LINE_END

            # Cycle through links
            keymap  TAB       NEXT_LINK
            keymap  C-n       NEXT_LINK
            keymap  ESC-TAB   PREV_LINK
            keymap  C-p       PREV_LINK

            # Follow link or submit form
            keymap  RET       GOTO_LINK
            keymap  SPC       NEXT_PAGE

            # History
            keymap  u         BACK
            keymap  C-h       HISTORY
            keymap  U         GOTO
            keymap  r         RELOAD
            keymap  R         RELOAD

            # In-page search
            keymap  /         SEARCH
            keymap  ?         SEARCH_BACK
            keymap  n         SEARCH_NEXT
            keymap  N         SEARCH_PREV

            # Tabs
            keymap  t         NEW_TAB
            keymap  T         TAB_LINK
            keymap  C-w       CLOSE_TAB
            keymap  ]         NEXT_TAB
            keymap  [         PREV_TAB
            keymap  }         NEXT_TAB
            keymap  {         PREV_TAB

            # Save link, page, queue.
            keymap  a         SAVE_LINK
            keymap  s         SAVE
            keymap  d         DOWNLOAD_LIST
            # Open, wget, copy URL.
            keymap  M         EXTERN

            # Bookmarks
            keymap  B         BOOKMARK
            keymap  M-b       ADD_BOOKMARK

            # Misc
            keymap  o         OPTIONS
            keymap  v         VIEW
            keymap  =         INFO
            keymap  C-l       REDRAW
            keymap  q         EXIT
            keymap  Q         EXIT
            keymap  :         COMMAND
            keymap  M-h       HELP

            # URL to clipboard
            keymap  y         PIPE_BUF
            keymap  Y         PIPE_SHELL
          '';

          home.file.".w3m/mailcap".text = ''
            image/*;             swayimg %s
            video/*;             mpv %s
            audio/*;             mpv %s
            application/pdf;     nixly-pdf %s
          '';
        })
      ];
    }
  ;

  images =
    # Swayimg opens images.
    { ... }:

    {
      config.home-manager.sharedModules = [
        ({ pkgs, ... }: {
          home.packages = with pkgs; [
            swayimg
          ];

          xdg.mimeApps = {
            enable = true;
            defaultApplications = {
              # Formats swayimg declares.
              "image/avif" = [ "swayimg.desktop" ];
              "image/bmp" = [ "swayimg.desktop" ];
              "image/gif" = [ "swayimg.desktop" ];
              "image/heif" = [ "swayimg.desktop" ];
              "image/jpeg" = [ "swayimg.desktop" ];
              "image/jpg" = [ "swayimg.desktop" ];
              "image/jxl" = [ "swayimg.desktop" ];
              "image/pbm" = [ "swayimg.desktop" ];
              "image/pjpeg" = [ "swayimg.desktop" ];
              "image/png" = [ "swayimg.desktop" ];
              "image/svg+xml" = [ "swayimg.desktop" ];
              "image/tiff" = [ "swayimg.desktop" ];
              "image/webp" = [ "swayimg.desktop" ];
              "image/x-bmp" = [ "swayimg.desktop" ];
              "image/x-exr" = [ "swayimg.desktop" ];
              "image/x-png" = [ "swayimg.desktop" ];
              "image/x-portable-anymap" = [ "swayimg.desktop" ];
              "image/x-portable-bitmap" = [ "swayimg.desktop" ];
              "image/x-portable-graymap" = [ "swayimg.desktop" ];
              "image/x-portable-pixmap" = [ "swayimg.desktop" ];
              "image/x-targa" = [ "swayimg.desktop" ];
              "image/x-tga" = [ "swayimg.desktop" ];
            };
          };
        })
      ];
    }
  ;

  video =
    { ... }:

    {
      config.home-manager.sharedModules = [
        ({ pkgs, ... }: {
          programs.mpv = {
            enable = true;
            package = pkgs.mpv;

            # Synced to the display rate.
            config = {
              # Wallpaper-themed OSD and uosc.
              include = "~/.local/state/nixly-theme/mpv.conf";
              # Best quality on modern GPUs.
              vo = "gpu-next";
              gpu-api = "vulkan";
              hwdec = "auto-safe";
              hwdec-codecs = "all";

              video-sync = "display-resample";
              interpolation = true;
              tscale = "oversample";
              # Free input lag win.
              video-latency-hacks = true;

              profile = "high-quality";
              scale = "ewa_lanczossharp";
              cscale = "ewa_lanczossharp";
              dscale = "mitchell";
              dither-depth = "auto";
              deband = true;
              deband-iterations = 2;
              deband-threshold = 35;
              deband-range = 16;
              deband-grain = 4;

              target-colorspace-hint = true;
              # HDR on SDR screens.
              tone-mapping = "bt.2446a";
              hdr-compute-peak = true;

              audio-channels = "auto-safe";
              audio-spdif = "ac3,dts,eac3,dts-hd,truehd";
              audio-exclusive = false;
              af = "scaletempo2";
              volume = 100;
              volume-max = 150;

              sub-auto = "fuzzy";
              sub-file-paths = "subs:subtitles:Subs";
              slang = "no,nob,nor,en,eng";
              alang = "no,nob,nor,jpn,en,eng";
              sub-font = "Noto Sans";
              sub-font-size = 42;
              sub-border-size = 2;
              sub-shadow-offset = 1;

              cache = true;
              cache-secs = 60;
              demuxer-max-bytes = "512MiB";
              demuxer-max-back-bytes = "256MiB";
              demuxer-readahead-secs = 30;

              keep-open = "yes";
              save-position-on-quit = true;
              watch-later-options-remove = "pause";
              screenshot-format = "png";
              screenshot-directory = "~/Pictures/mpv";

              osd-bar = true;
              osd-font = "JetBrainsMono Nerd Font";
              osd-font-size = 28;

              ytdl-format = "bestvideo[height<=?2160][vcodec!=?vp9]+bestaudio/best";
              script-opts = "ytdl_hook-ytdl_path=${pkgs.yt-dlp}/bin/yt-dlp";
            };

            # Auto-activated on match.
            profiles = {
              # mpv --profile=tv.
              "tv" = {
                profile-desc = "TV / HTPC playback";
                fullscreen = true;
                interpolation = true;
                tscale = "oversample";
                video-sync = "display-resample";
                deband = true;
                tone-mapping = "bt.2446a";
                hdr-compute-peak = true;
              };

              "high-res" = {
                profile-desc = "auto profile for >=1440p";
                profile-cond = "(width or 0) >= 1440";
                scale = "ewa_lanczos";
                cscale = "ewa_lanczos";
                deband = false;
              };

              "low-res" = {
                profile-desc = "auto profile for <720p";
                profile-cond = "(width or 0) < 1280";
                scale = "ewa_lanczossharp";
                cscale = "ewa_lanczossharp";
                deband = true;
              };

              "anime" = {
                profile-desc = "Anime tuning";
                profile-cond = "string.match(p.filename, '%.[Aa]nime') ~= nil";
                deband = true;
                deband-iterations = 4;
                deband-grain = 24;
                scale = "ewa_lanczossharp";
                cscale = "mitchell";
              };
            };

            bindings = {
              "RIGHT" = "seek 5";
              "LEFT" = "seek -5";
              "UP" = "seek 60";
              "DOWN" = "seek -60";
              "Shift+RIGHT" = "seek 30";
              "Shift+LEFT" = "seek -30";

              "[" = "multiply speed 0.9091";
              "]" = "multiply speed 1.1";
              "BS" = "set speed 1.0";

              "WHEEL_UP" = "add volume 5";
              "WHEEL_DOWN" = "add volume -5";
              "m" = "cycle mute";

              "j" = "cycle sub";
              "J" = "cycle sub down";
              "#" = "cycle audio";

              "f" = "cycle fullscreen";
              "TAB" = "cycle ontop";
              "i" = "script-binding stats/display-stats-toggle";
              "I" = "script-binding stats/display-stats";
              "p" = "cycle pause";
              "q" = "quit-watch-later";
              "Q" = "quit";

              "Ctrl+t" = "apply-profile tv";

              "." = "frame-step";
              "," = "frame-back-step";

              "s" = "screenshot";
              "S" = "screenshot video";
            };

            scripts = with pkgs.mpvScripts; [
              mpris # MPRIS for media-keys / control center
              thumbfast # Hurtig thumbnail-preview ved seeking
              autoload # Auto-load neste fil i mappa
              uosc # Moderne OSC/UI
              quality-menu # YouTube quality picker
            ];
          };

          # Streaming needs yt-dlp.
          home.packages = with pkgs; [
            yt-dlp
          ];
        })
      ];
    }
  ;
in
{
  imports = [
    everyday
    browser
    feeds
    textBrowser
    images
    video
  ];
}
