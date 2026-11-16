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
  home.packages = [ (pkgs.runCommand "nixly-kdeglobals" { } ''
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
  '') ];

  # Written by nixlytile's wallpaper theme.
  xdg.configFile."kdeglobals".source =
    config.lib.file.mkOutOfStoreSymlink "${config.xdg.stateHome}/nixly-theme/kdeglobals-colors";
}
