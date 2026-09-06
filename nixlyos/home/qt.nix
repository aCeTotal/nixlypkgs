{ pkgs, ... }:

{
  # Qt/KDE theming for Dolphin and friends outside Plasma, reading kdeglobals.
  # platformTheme.package is explicit to avoid pulling in the whole Plasma closure.
  qt = {
    enable = true;
    platformTheme = {
      name = "kde";
      package = [ pkgs.kdePackages.plasma-integration ];
    };
    style = {
      name = "breeze";
      package = [ pkgs.kdePackages.breeze ];
    };
  };

  # The colours must be spelled out as [Colors:*] groups; ColorScheme=BreezeDark
  # alone is just a name and still yields a light theme.
  xdg.configFile."kdeglobals".source = pkgs.runCommand "kdeglobals" { } ''
    cp ${pkgs.kdePackages.breeze}/share/color-schemes/BreezeDark.colors $out
    chmod +w $out
    cat >> $out <<'EOF'

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
  '';
}
