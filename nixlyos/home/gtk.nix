{ pkgs, ... }:

{
  home.pointerCursor = {
    enable = true;
    gtk.enable = true;
    package = pkgs.bibata-cursors;
    name = "Bibata-Modern-Ice";
    size = 21;
  };

  gtk = {
    enable = true;
    theme = {
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
