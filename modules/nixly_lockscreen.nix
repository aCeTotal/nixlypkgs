{ config, lib, pkgs, ... }:

let
  cfg = config.services.nixly_lockscreen;
in
{
  options.services.nixly_lockscreen = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Enable the nixly_lockscreen Wayland session locker. Defaults to true:
        importing this module activates the lockscreen + idle daemon out of the box.
      '';
    };

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.nixly_lockscreen;
      description = "The nixly_lockscreen package.";
    };

    idleTimeoutSeconds = lib.mkOption {
      type = lib.types.int;
      default = 180;
      description = ''
        Seconds of user inactivity before the lockscreen is triggered.
        The compositor's idle inhibitor (used by mpv, browsers, etc.) is
        respected, so fullscreen video does not trigger the lock.
      '';
    };

    pamService = lib.mkOption {
      type = lib.types.str;
      default = "nixly-lockscreen";
      description = ''
        PAM service name. The binary defaults to this name; override
        NIXLY_LOCKSCREEN_PAM_SERVICE if you change this.
      '';
    };

    maskCtrlAltDel = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Mask ctrl-alt-del.target so Ctrl+Alt+Del cannot reboot the machine.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];

    security.pam.services.${cfg.pamService} = {
      text = ''
        auth     sufficient ${pkgs.linux-pam}/lib/security/pam_unix.so likeauth try_first_pass
        auth     required   ${pkgs.linux-pam}/lib/security/pam_deny.so
        account  required   ${pkgs.linux-pam}/lib/security/pam_unix.so
        password required   ${pkgs.linux-pam}/lib/security/pam_deny.so
        session  required   ${pkgs.linux-pam}/lib/security/pam_unix.so
      '';
    };

    # Auto-start the idle daemon for every graphical user session. Wayland
    # compositors that activate `graphical-session.target` (Hyprland, Sway,
    # GNOME, KDE …) will start nixly-idled automatically.
    systemd.user.services.nixly-idled = {
      description = "nixly_lockscreen idle daemon";
      partOf = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];
      wantedBy = [ "graphical-session.target" ];
      environment = {
        NIXLY_IDLE_TIMEOUT_MS = toString (cfg.idleTimeoutSeconds * 1000);
        NIXLY_LOCK_CMD = "${cfg.package}/bin/nixly-lockscreen";
        NIXLY_LOCKSCREEN_PAM_SERVICE = cfg.pamService;
      };
      serviceConfig = {
        Type = "simple";
        ExecStart = "${cfg.package}/bin/nixly-idled";
        Restart = "on-failure";
        RestartSec = 3;
      };
    };

    # System-side TTY/sysrq lockdown helper used by the lockscreen
    # while the screen is locked.
    systemd.services.nixly-lockguard = {
      description = "nixly_lockscreen TTY/sysrq lockdown helper";
      wantedBy = [ "multi-user.target" ];
      after = [ "systemd-logind.service" ];
      serviceConfig = {
        ExecStart = "${cfg.package}/bin/nixly-lockguard";
        Restart = "always";
        RestartSec = 1;
        User = "root";
        RuntimeDirectory = "nixly-lockguard";
        AmbientCapabilities = [ "CAP_SYS_TTY_CONFIG" "CAP_SYS_ADMIN" ];
        CapabilityBoundingSet = [ "CAP_SYS_TTY_CONFIG" "CAP_SYS_ADMIN" ];
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        PrivateNetwork = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        SystemCallArchitectures = "native";
        SystemCallFilter = [ "@system-service" "@privileged" ];
        ReadWritePaths = [ "/proc/sys/kernel/sysrq" ];
      };
    };

    systemd.suppressedSystemUnits = lib.mkIf cfg.maskCtrlAltDel [
      "ctrl-alt-del.target"
    ];
  };
}
