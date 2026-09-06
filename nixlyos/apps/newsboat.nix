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
