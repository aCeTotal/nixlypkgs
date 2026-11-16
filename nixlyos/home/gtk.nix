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
