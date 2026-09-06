{ pkgs, nixlyUser, ... }:

let
  lockscreen = pkgs.nixly_lockscreen;
  pamService = "nixly-lockscreen";
  idleTimeoutSeconds = 180;
in
{
  environment.systemPackages = [ lockscreen ];

  security.pam.services.${pamService} = {
    text = ''
      auth     sufficient ${pkgs.linux-pam}/lib/security/pam_unix.so likeauth try_first_pass
      auth     required   ${pkgs.linux-pam}/lib/security/pam_deny.so
      account  required   ${pkgs.linux-pam}/lib/security/pam_unix.so
      password required   ${pkgs.linux-pam}/lib/security/pam_deny.so
      session  required   ${pkgs.linux-pam}/lib/security/pam_unix.so
    '';
  };

  systemd.user.services.nixly-idled = {
    description = "nixly_lockscreen idle daemon";
    partOf = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];
    wantedBy = [ "graphical-session.target" ];
    environment = {
      NIXLY_IDLE_TIMEOUT_MS = toString (idleTimeoutSeconds * 1000);
      NIXLY_LOCK_CMD = "${lockscreen}/bin/nixly-lockscreen";
      NIXLY_LOCKSCREEN_PAM_SERVICE = pamService;
    };
    serviceConfig = {
      Type = "simple";
      ExecStart = "${lockscreen}/bin/nixly-idled";
      Restart = "on-failure";
      RestartSec = 3;
    };
  };

  systemd.services.nixly-lockguard = {
    description = "nixly_lockscreen TTY/sysrq lockdown helper";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-logind.service" ];
    serviceConfig = {
      ExecStart = "${lockscreen}/bin/nixly-lockguard";
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

  # Lock before the machine sleeps so lid-open lands on the password prompt,
  # the exact session restored behind it. Launches the session-lock client in
  # the user's Wayland session and waits briefly for the lock surface to come
  # up before suspend proceeds. KillMode=none so the backgrounded locker is not
  # reaped when this oneshot exits — it must live across the suspend/resume and
  # until the user authenticates. A redundant locker (idle daemon also fired)
  # gets `finished` from the compositor and exits: the lock is single-holder.
  systemd.services.nixly-lock-before-sleep = {
    description = "Lock the Wayland session before sleep";
    before = [ "systemd-suspend.service" "systemd-hibernate.service" "systemd-suspend-then-hibernate.service" ];
    wantedBy = [ "systemd-suspend.service" "systemd-hibernate.service" "systemd-suspend-then-hibernate.service" ];
    serviceConfig = {
      Type = "oneshot";
      KillMode = "none";
      User = nixlyUser;
      Group = "users";
      Environment = [
        "XDG_RUNTIME_DIR=/run/user/1000"
        "WAYLAND_DISPLAY=wayland-0"
        "NIXLY_LOCKSCREEN_PAM_SERVICE=${pamService}"
      ];
      ExecStart = pkgs.writeShellScript "nixly-lock-before-sleep" ''
        ${lockscreen}/bin/nixly-lockscreen &
        ${pkgs.coreutils}/bin/sleep 0.5
      '';
    };
  };

  # Ctrl+Alt+Del must not reboot the machine.
  systemd.suppressedSystemUnits = [ "ctrl-alt-del.target" ];
}
