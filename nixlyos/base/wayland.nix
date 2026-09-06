{ config, lib, pkgs, ... }:

{
  xdg.portal = {
    enable = true;
    extraPortals = with pkgs; [
      xdg-desktop-portal-wlr
      xdg-desktop-portal-gtk
    ];
    config.common.default = "*";
  };

  programs.xwayland.enable = true;
  programs.xwayland.package = pkgs.xwayland;

  security.polkit.enable = true;
  services.dbus.enable = true;

  environment.systemPackages = with pkgs; [
    swaybg
  ];

  environment.sessionVariables = {
    NIXOS_OZONE_WL = "1";
    QT_QPA_PLATFORM = "wayland";
    MOZ_ENABLE_WAYLAND = "1";
    GTK_USE_PORTAL = "1";
  };

}
