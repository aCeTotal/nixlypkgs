{ pkgs, lib, ... }:

{
  services.displayManager.sessionPackages = [ pkgs.nixlytile ];
  services.displayManager.defaultSession = "nixlytile";

  environment.systemPackages = [ pkgs.nixlytile ];

  xdg.portal = {
    enable = true;
    # Shortcuts and FileChooser from nixlytile.
    extraPortals = with pkgs; [ xdg-desktop-portal-gtk xdg-desktop-portal-wlr nixlytile ];
    config.nixlytile = {
      default = lib.mkForce [ "wlr" "gtk" ];
      "org.freedesktop.impl.portal.GlobalShortcuts" = [ "nixlytile" ];
      "org.freedesktop.impl.portal.FileChooser" = [ "nixlytile" ];
    };
  };

  systemd.suppressedSystemUnits = [
    "systemd-backlight@backlight:intel_backlight.service"
  ];

  environment.sessionVariables = {
    NIXOS_OZONE_WL = "1";
    XDG_CURRENT_DESKTOP = "nixlytile";
    XDG_SESSION_DESKTOP = "nixlytile";
  };

  # No services.xserver.enable: Wayland-only session, so the full Xorg stack was
  # closure and boot bloat that nothing started.
  security.polkit.enable = true;

  # The compositor starts this at login, but only if the unit file is in
  # /etc/systemd/user; without it graphical-session.target never activates.
  systemd.user.targets.nixlytile-session = {
    description = "nixlytile compositor session";
    bindsTo = [ "graphical-session.target" ];
    wants = [ "graphical-session-pre.target" ];
    after = [ "graphical-session-pre.target" ];
  };

  systemd.user.services.polkit-gnome-authentication-agent-1 = {
    description = "polkit-gnome-authentication-agent-1";
    wantedBy = [ "graphical-session.target" ];
    wants = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];
    # Agenten er X11-basert og dør med "cannot open display :0" til
    # Xwayland er oppe; med default start-limit (5 på 10 s) ga
    # RestartSec=1 permanent failed unit hver boot -> ingen
    # polkit-dialoger. Ubegrenset retry til display finnes.
    unitConfig.StartLimitIntervalSec = 0;
    # GTK would pull gvfsd in.
    environment.GIO_USE_VFS = "local";
    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1";
      Restart = "on-failure";
      RestartSec = 2;
      TimeoutStopSec = 10;
    };
  };

  # File dialogs browse local files.
  systemd.user.services.xdg-desktop-portal-gtk.environment.GIO_USE_VFS = "local";
}
