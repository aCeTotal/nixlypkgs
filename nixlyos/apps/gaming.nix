{ config, lib, pkgs, ... }:

{
  imports = [ ./steam ];

  programs.gamemode = {
    enable = true;
    settings = {
      general = {
        renice = 10;
        ioprio = 0;               # Real-time I/O priority
        inotify = 131072;         # Unity games and big mods hit the 8192 ceiling
        inhibit_screensaver = 1;
        softrealtime = "auto";
        reaper_freq = 5;          # Check for game exit every 5s
        # No desiredgov/defaultgov: perf.nix owns the governor.
      };
      gpu = {
        apply_gpu_optimisations = "accept-responsibility";
        gpu_device = 0;
        nv_powermizer_mode = 1;   # Prefer max performance for Nvidia
        nv_core_clock_mhz_offset = 0;
        nv_mem_clock_mhz_offset = 0;
        amd_performance_level = "high"; # AMD DPM to max while gaming; no-op elsewhere
      };
      cpu = {
        park_cores = "no";
        # nixlytile owns CPU affinity; two writers raced.
        pin_cores = "no";
      };
      # No custom start/end: nixlytile shows its own "Game Mode On" notification.
    };
  };

  environment.systemPackages = with pkgs; [
    (geforce-now.override { browserCommand = "google-chrome-stable"; })
    steamcmd
    mangohud
    goverlay
    vkbasalt
    lutris
    protonup-ng
    protontricks
    wineWow64Packages.staging
    winetricks
    dxvk
    vkd3d
    linuxConsoleTools # jstest and input debugging
    evtest

    # Vulkan
    vulkan-loader
    vulkan-validation-layers
    vulkan-tools
    pkgsi686Linux.vulkan-loader # 32-bit Vulkan for Steam games
    pkgsi686Linux.mangohud      # so the fps cap also reaches 32-bit games
  ] ++ lib.optional (pkgs ? low-latency-layer)
    # Implicit Vulkan layer: VK_NV_low_latency2 (Reflex) + VK_AMD_anti_lag
    # on any GPU. Opt-in per game — gamewrap sets LOW_LATENCY_LAYER=1.
    # From nixlypkgs; the guard keeps eval green until that rev is pushed.
    pkgs.low-latency-layer
  ++ (with pkgs; [

    libnotify           # gamemode notifications
    schedtool

    mpv
    yt-dlp
  ]);

  hardware.xpadneo.enable = true;   # Xbox Bluetooth
  hardware.xone.enable = true;      # Xbox USB dongle and wired pads

  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
    settings = {
      General = {
        Experimental = true;
        KernelExperimental = true;
        ControllerMode = "dual";
        FastConnectable = true;

        # Controller pairing.
        Privacy = "device";
        JustWorksRepairing = "always";
        Class = "0x000100";
      };
      Policy = {
        AutoEnable = true;
        ReconnectAttempts = 15;
        ReconnectIntervals = "1,2,4,8,16,32,64,128";
        ReconnectUUIDs = "00001124-0000-1000-8000-00805f9b34fb,00001200-0000-1000-8000-00805f9b34fb";
      };
      LE = {
        MinAdvertisementInterval = 32;
        MaxAdvertisementInterval = 50;
        ScanIntervalAutoConnect = 60;
        # 30/60 = 50 % duty jammed 2.4 GHz WiFi (bt_coex is off for the
        # AX210 crash workaround); 15/60 still reconnects a pad in seconds.
        ScanWindowAutoConnect = 15;
      };
      GATT = {
        Cache = "yes";
        Channels = 3;
        KeySize = 7;
      };
    };
  };

  services.udev.extraRules = ''
    # Xbox Controllers
    SUBSYSTEM=="usb", ATTR{idVendor}=="045e", ATTR{idProduct}=="028e", MODE="0666"
    SUBSYSTEM=="usb", ATTR{idVendor}=="045e", ATTR{idProduct}=="028f", MODE="0666"
    SUBSYSTEM=="usb", ATTR{idVendor}=="045e", ATTR{idProduct}=="0291", MODE="0666"
    SUBSYSTEM=="usb", ATTR{idVendor}=="045e", ATTR{idProduct}=="02d1", MODE="0666"
    SUBSYSTEM=="usb", ATTR{idVendor}=="045e", ATTR{idProduct}=="02dd", MODE="0666"
    SUBSYSTEM=="usb", ATTR{idVendor}=="045e", ATTR{idProduct}=="02e3", MODE="0666"
    SUBSYSTEM=="usb", ATTR{idVendor}=="045e", ATTR{idProduct}=="02ea", MODE="0666"
    SUBSYSTEM=="usb", ATTR{idVendor}=="045e", ATTR{idProduct}=="0b00", MODE="0666"
    SUBSYSTEM=="usb", ATTR{idVendor}=="045e", ATTR{idProduct}=="0b12", MODE="0666"

    # Xbox Wireless Adapter
    SUBSYSTEM=="usb", ATTR{idVendor}=="045e", ATTR{idProduct}=="02fe", MODE="0666"
    SUBSYSTEM=="usb", ATTR{idVendor}=="045e", ATTR{idProduct}=="0719", MODE="0666"

    # PlayStation Controllers (DualShock 4, DualSense)
    SUBSYSTEM=="usb", ATTR{idVendor}=="054c", ATTR{idProduct}=="05c4", MODE="0666"
    SUBSYSTEM=="usb", ATTR{idVendor}=="054c", ATTR{idProduct}=="09cc", MODE="0666"
    SUBSYSTEM=="usb", ATTR{idVendor}=="054c", ATTR{idProduct}=="0ce6", MODE="0666"
    SUBSYSTEM=="usb", ATTR{idVendor}=="054c", ATTR{idProduct}=="0df2", MODE="0666"

    # Nintendo Switch Pro Controller
    SUBSYSTEM=="usb", ATTR{idVendor}=="057e", ATTR{idProduct}=="2009", MODE="0666"

    # 8BitDo Controllers
    SUBSYSTEM=="usb", ATTR{idVendor}=="2dc8", MODE="0666"

    # Valve Steam Controller: uaccess fallback for every Valve PID.
    SUBSYSTEM=="usb", ATTRS{idVendor}=="28de", MODE="0660", TAG+="uaccess"
    KERNEL=="hidraw*", ATTRS{idVendor}=="28de", MODE="0660", TAG+="uaccess"
    KERNEL=="hidraw*", KERNELS=="*28DE:*", MODE="0660", TAG+="uaccess"

    # Generic game controllers; 0660 not 0666 so event nodes are not world-readable.
    KERNEL=="js[0-9]*", MODE="0660", GROUP="input", TAG+="uaccess"
    KERNEL=="event[0-9]*", SUBSYSTEM=="input", MODE="0660", GROUP="input", TAG+="uaccess"

  '';

  # ntsync for Wine/Proton; own 70-file since uaccess in 99-local.rules is too late for ACLs.
  services.udev.packages = [
    (pkgs.writeTextFile {
      name = "ntsync-udev-rules";
      destination = "/etc/udev/rules.d/70-ntsync.rules";
      text = ''
        KERNEL=="ntsync", MODE="0660", TAG+="uaccess"
      '';
    })
  ];

  # Type=simple + bluetooth.target so it never blocks graphical.target.
  systemd.services.bluetooth-controller-connect = {
    description = "Auto-connect paired Bluetooth controllers";
    after = [ "bluetooth.service" ];
    wants = [ "bluetooth.service" ];
    wantedBy = [ "bluetooth.target" ];

    serviceConfig = {
      Type = "simple";
      ExecStart = pkgs.writeShellScript "bt-connect" ''
        for i in {1..10}; do
          ${pkgs.bluez}/bin/bluetoothctl show | grep -q "Powered: yes" && break
          sleep 1
        done

        ${pkgs.bluez}/bin/bluetoothctl devices Paired | while read -r _ mac name; do
          ${pkgs.bluez}/bin/bluetoothctl connect "$mac" &
        done
        wait
      '';
    };
  };

  # Reconnect after sleep/hibernate only, not periodically.
  systemd.services.bluetooth-controller-resume = {
    description = "Reconnect Bluetooth controllers after resume";
    after = [ "suspend.target" "hibernate.target" "hybrid-sleep.target" ];
    wantedBy = [ "suspend.target" "hibernate.target" "hybrid-sleep.target" ];

    serviceConfig = {
      Type = "oneshot";
      ExecStartPre = "${pkgs.coreutils}/bin/sleep 3";
      ExecStart = pkgs.writeShellScript "bt-resume" ''
        # Restart Bluetooth to clear stale connections.
        ${pkgs.systemd}/bin/systemctl restart bluetooth.service
        sleep 2

        ${pkgs.bluez}/bin/bluetoothctl devices Paired | while read -r _ mac name; do
          echo "Reconnecting after resume: $name ($mac)"
          ${pkgs.bluez}/bin/bluetoothctl connect "$mac" &
        done
        wait
      '';
    };
  };

  boot = {
    extraModulePackages = with config.boot.kernelPackages; [
      xpadneo
      xone
    ];

    kernelModules = [
      "uinput"
      "hid-generic"
      "hid-sony"
      "hid-microsoft"
      "hid-nintendo"
    ]
    # Only on 6.14+; older kernels fail systemd-modules-load.
    ++ lib.optional
      (lib.versionAtLeast config.boot.kernelPackages.kernel.version "6.14")
      "ntsync";

    extraModprobeConfig = ''
      # Fix ERTM for Xbox Bluetooth controllers.
      options bluetooth disable_ertm=Y

      # xpadneo stability.
      options xpadneo disable_deadzones=0
      options xpadneo trigger_rumble_mode=0
    '';
    # No usbhid mousepoll: it capped every USB mouse at 250 Hz.
  };

  # Controller access needs the input group.
  users.groups.input = {};
}
