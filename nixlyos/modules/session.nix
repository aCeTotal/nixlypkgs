{ config, lib, pkgs, hwData, ... }:

let
  isHtpc = config.nixlyos.mode == "htpc";

  wayland = {
    xdg.portal = {
      enable = true;
      extraPortals = with pkgs; [ xdg-desktop-portal-wlr xdg-desktop-portal-gtk nixlytile ];
      config.common.default = "*";
      # Shortcuts and file picker.
      config.nixlytile = {
        default = lib.mkForce [ "wlr" "gtk" ];
        "org.freedesktop.impl.portal.GlobalShortcuts" = [ "nixlytile" ];
        "org.freedesktop.impl.portal.FileChooser" = [ "nixlytile" ];
      };
    };

    programs.xwayland.enable = true;
    programs.xwayland.package = pkgs.xwayland;

    # Apps skip icon scans.
    gtk.iconCache.enable = true;

    # Wayland only, no Xorg.
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
      XDG_CURRENT_DESKTOP = "nixlytile";
      XDG_SESSION_DESKTOP = "nixlytile";
    };
  };

  compositor = {
    services.displayManager.sessionPackages = [ pkgs.nixlytile ];
    services.displayManager.defaultSession = "nixlytile";

    environment.systemPackages = [ pkgs.nixlytile ];

    # GPU queue priority over clients.
    security.wrappers.nixlytile = {
      owner = "root";
      group = "root";
      capabilities = "cap_sys_nice+ep";
      # Restores what the wrapper strips.
      source = "${pkgs.writeShellScript "nixlytile-session" ''
        . /etc/set-environment
        exec ${pkgs.nixlytile}/bin/nixlytile "$@"
      ''}";
    };

    systemd.suppressedSystemUnits = [
      "systemd-backlight@backlight:intel_backlight.service"
    ];

    # Activates graphical-session.target.
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
      # Retries until Xwayland is up.
      unitConfig.StartLimitIntervalSec = 0;
      # GTK would pull gvfsd in.
      environment.GIO_USE_VFS = "local";
      # GTK would start every portal.
      environment.GTK_USE_PORTAL = "0";
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

    # Up at login, not on first app.
    systemd.user.services.xdg-desktop-portal.wantedBy = [ "graphical-session.target" ];
  };

  login = {
    services.displayManager.sddm = {
      enable = true;
      wayland.enable = true;
      autoNumlock = true;
      package = pkgs.kdePackages.sddm;
      theme = "sddm-astronaut-theme";
      extraPackages = with pkgs.kdePackages; [
        qtmultimedia
        qtsvg
        qtvirtualkeyboard
      ];
    };

    environment.systemPackages = [ pkgs.sddm-astronaut ];
  };

  input = {
    services.libinput.enable = true;
    services.xserver.xkb.layout = lib.mkForce "no";
    services.xserver.xkb.variant = lib.mkForce "";
    console.keyMap = lib.mkForce "no";

    # nixlytile reapplies it live.
    environment.etc."nixlyos/input.conf".text = ''
      accel-profile=adaptive
      accel-speed=0.00
      natural-scroll=false
      left-handed=false
      middle-button-emulation=false
      scroll-method=wheel
      button-map=lrm
      keyboard-layout=no
      keyboard-variant=
      repeat-delay=300
      repeat-rate=100
    '';

    boot.kernelModules = [ "i2c-dev" ];

    # Exec, the device scan blocked boot.
    systemd.services.nixly-input-hardware = {
      description = "Apply nixlycc mouse and keyboard hardware settings";
      wantedBy = [ "multi-user.target" ];
      after = [ "openrgb.service" ];
      path = with pkgs; [ openrgb ];
      serviceConfig.Type = "exec";
      script = ''
        openrgb --noautoconnect --mode rainbow --color 00beff --brightness 100 || true
      '';
    };
  };

  # Storage popup's root helper.
  storage = {
    systemd.services.nixly-diskd = {
      description = "nixlytile disk management helper";
      wantedBy = [ "multi-user.target" ];
      path = with pkgs; [
        parted
        util-linux
        e2fsprogs
        btrfs-progs
        xfsprogs
        dosfstools
        exfatprogs
        ntfs3g
        systemd
      ];
      serviceConfig = {
        Type = "exec";
        ExecStart = "${pkgs.nixlytile}/bin/nixly-diskd";
        Restart = "on-failure";
        RestartSec = 5;
        # Mounts stay visible system-wide.
        NoNewPrivileges = true;
        ProtectSystem = "full";
        ProtectHome = false;
        ProtectHostname = true;
        ProtectKernelModules = true;
        ProtectKernelLogs = true;
        ProtectControlGroups = true;
        PrivateNetwork = true;
        RestrictAddressFamilies = [ "AF_UNIX" ];
        RestrictNamespaces = true;
        RestrictRealtime = true;
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        SystemCallArchitectures = "native";
        SystemCallFilter = [ "@system-service" "@mount" "@raw-io" ];
        CapabilityBoundingSet = [
          "CAP_SYS_ADMIN"
          "CAP_CHOWN"
          "CAP_FOWNER"
          "CAP_DAC_OVERRIDE"
          "CAP_MKNOD"
          "CAP_SYS_RAWIO"
        ];
      };
    };
  };

  home =
    let
      hasNvidia = hwData.detected.nvidia != "";
      # Black behind fullscreen video.
      rootColor = if isHtpc then "#000000ff" else "#222222ff";
      fullscreenBg = if isHtpc then "#000000ff" else "#1a1a1aff";
    in
    {
      home.packages = with pkgs; [
        grim
        slurp
        wl-clipboard
        libnotify
        swappy
        swaybg
        clipman
        fuzzel
        kdePackages.breeze-icons
        kdePackages.qtwayland
        samba
        cifs-utils
        foot
        brightnessctl
        playerctl
        wireplumber
        xwayland-satellite
        xrandr
        socat
        jq
        nixly_launcher
        nautilus
        file-roller
        ffmpegthumbnailer
      ];

      home.file."Pictures/wallpapers/mountains.jpg".source = "${pkgs.nixly-wallpaper}/share/wallpapers/mountains.jpg";

      # Nautilus ignores the GTK theme.
      dconf.settings."org/gnome/desktop/interface".color-scheme = "prefer-dark";

      xdg.mimeApps.defaultApplications."inode/directory" =
        [ "org.gnome.Nautilus.desktop" ];

      # Dead SMB servers never hang.
      home.file.".smb/smb.conf".text = ''
        [global]
            client min protocol = SMB2
            client max protocol = SMB3
            client ipc max protocol = SMB3
            # WINS lookups hang.
            name resolve order = host bcast
            # Give up after 3 s.
            client connection timeout = 3000
            socket options = TCP_NODELAY IPTOS_LOWDELAY
      '';

      xdg.configFile."nixlytile/config.kdl".text = ''
        // Keybindings live in bindings.conf.

        appearance {
            gaps 4
            border-px 1
            smartgaps           false
            sloppy-focus        true
            bypass-surface-visibility false
            gaps-enabled        true
            root-color          "${rootColor}"
            border-color        "#595959ff"
            focus-color         "#00beffff"
            urgent-color        "#ff0000ff"
            fullscreen-bg       "${fullscreenBg}"
            resize-factor       0.0002
            resize-interval-ms  8
            resize-min-pixels   1.0
            resize-ratio-epsilon 0.001
            lock-cursor         false
        }

        input {
            keyboard {
                layout       "no"
                repeat-delay 300
                repeat-rate  100
            }
            touchpad {
                tap                     true
                tap-and-drag            true
                drag-lock               true
                natural-scroll          true
                disable-while-typing    true
                left-handed             false
                middle-button-emulation false
                scroll-method   "2fg"
                click-method    "button-areas"
                send-events     "enabled"
                accel-profile   "adaptive"
                accel-speed     0.0
                button-map      "lrm"
            }
        }

        // Unreal-dialoger flyter, editoren flislegges.
        window-rule {
            app-id   "UnrealEditor"
            title    "Unreal Engine 5"
            floating true
        }
        window-rule {
            app-id   "UnrealEditor"
            title    "New Project"
            floating true
        }
        window-rule {
            app-id   "UnrealEditor"
            title    "Create Project"
            floating true
        }

        // Citrix er ikke et spill.
        window-rule {
            app-id     "Wfica"
            game       false
            fullscreen false
        }

        // GFN-vinduet ligner en splash.
        window-rule {
            app-id "GeForceNOW"
            game   false
        }

        // Gaea er et verktøy.
        window-rule {
            app-id     "gaea"
            game       false
            fullscreen false
        }
        // Viewporten posisjonerer seg selv.
        window-rule {
            app-id   "gaea.viewport"
            embedded true
        }

        modkey      "Super"
        monitorkey  "Ctrl"

        // Surround-oppløsning spenner alle skjermer.
        game-span "auto"

        ${lib.optionalString hasNvidia ''
        // NVIDIA avviser IN_FENCE_FD.
        game-late-latch false
        ''}
        wallpaper "~/Pictures/wallpapers/mountains.jpg"

        // Debug koster i frame-pathen.
        log-level "info"

        ${if isHtpc then ''
        // Statusbar alltid skjult.
        htpc true

        // Kun nixlymedia ved boot.
        autostart "htpc-switch nixlymedia"
        '' else ''
        // Én prosess per linje.
        autostart "sh -c 'wl-paste --type text --watch clipman store --no-persist'"
        autostart "sh -c 'wl-paste --primary --type text --watch clipman store --no-persist'"
        // Varmer spill når musen hviler.
        autostart "nixly-activity-prewarm"
        // Utsatt for å skåne innloggingen.
        autostart "sh -c 'sleep 8; exec appd'"
        ''}
      '';
    };
in
{
  imports = [
    wayland
    compositor
    login
    input
    storage
  ];

  home-manager.sharedModules = [ home ];
}
