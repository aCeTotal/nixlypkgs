{ config, lib, pkgs, hwData, nixlyUser, ... }:

let
  # v3 SIGILLs before AVX2.
  protonNixlyos =
    if hwData.resources.cpuLevel >= 3
    then pkgs.proton-nixlyos
    else pkgs.proton-nixlyos-generic;

  # Skips work while games run.
  prewarmGate = pkgs.writeShellScript "nixly-prewarm-gate" ''
    set -u
    # Game active?
    if ${pkgs.systemd}/bin/systemctl is-active -q nixly-gametune.service; then
      exit 1
    fi
    # Launches gametune misses.
    ${pkgs.procps}/bin/pgrep -x wineserver >/dev/null 2>&1 && exit 1
    ${pkgs.procps}/bin/pgrep -x retroarch >/dev/null 2>&1 && exit 1
    ${pkgs.procps}/bin/pgrep -x gamescope >/dev/null 2>&1 && exit 1
    ${pkgs.procps}/bin/pgrep -x reaper >/dev/null 2>&1 && exit 1
    # Load over half the cores.
    ncpu=$(${pkgs.coreutils}/bin/nproc)
    ${pkgs.gawk}/bin/awk -v n="$ncpu" '{exit ($1 > n/2) ? 1 : 0}' /proc/loadavg \
      || exit 1
    # Under 25 % free RAM.
    ${pkgs.gawk}/bin/awk '/MemTotal/{t=$2} /MemAvailable/{a=$2}
      END{exit (a < t/4) ? 1 : 0}' /proc/meminfo || exit 1
    exit 0
  '';

  steam = {
    programs.steam = {
      enable = true;
      remotePlay.openFirewall = false;
      dedicatedServer.openFirewall = false;

      package = pkgs.steam.override {
        # 64-bit steamrt3c client.
        extraEnv.STEAM_FORCE_CLIENT = "steamrt64";
        # Never fatal, every launch.
        extraPreBwrapCmds = "${pkgs.nixly-steam-autoconfig.override { protonTool = protonNixlyos; }} || true";
      };

      extraCompatPackages = [ protonNixlyos ];

      extraPackages = with pkgs; [
        libGL
        libglvnd
      ];
    };

    hardware.steam-hardware.enable = true;
  };

  # nixlytile and gametune own priority.
  tools = {
    environment.systemPackages = with pkgs; [
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
      linuxConsoleTools
      evtest

      vulkan-loader
      vulkan-validation-layers
      vulkan-tools
      pkgsi686Linux.vulkan-loader
      # Fps cap reaches 32-bit games.
      pkgsi686Linux.mangohud
    ] ++ lib.optional (pkgs ? low-latency-layer)
      # Reflex and Anti-Lag layer.
      pkgs.low-latency-layer
    ++ lib.optionals (pkgs ? nixly-vrs) [
      pkgs.nixly-vrs
      pkgs.pkgsi686Linux.nixly-vrs
    ]
    ++ (with pkgs; [
      schedtool
      mpv
      yt-dlp
    ]);
  };

  controllers = {
    # In-tree xone needs dongle firmware.
    hardware.firmware = [ pkgs.xone-dongle-firmware ];
    # Its Wi-Fi driver grabs the dongle.
    boot.blacklistedKernelModules = [ "mt76x2u" ];

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

      # Every Valve PID
      SUBSYSTEM=="usb", ATTRS{idVendor}=="28de", MODE="0660", TAG+="uaccess"
      KERNEL=="hidraw*", ATTRS{idVendor}=="28de", MODE="0660", TAG+="uaccess"
      KERNEL=="hidraw*", KERNELS=="*28DE:*", MODE="0660", TAG+="uaccess"

      # Generic pads, not world-readable
      KERNEL=="js[0-9]*", MODE="0660", GROUP="input", TAG+="uaccess"
      KERNEL=="event[0-9]*", SUBSYSTEM=="input", MODE="0660", GROUP="input", TAG+="uaccess"

    '';

    # 99-local.rules is too late.
    services.udev.packages = [
      (pkgs.writeTextFile {
        name = "ntsync-udev-rules";
        destination = "/etc/udev/rules.d/70-ntsync.rules";
        text = ''
          KERNEL=="ntsync", MODE="0660", TAG+="uaccess"
        '';
      })
    ];

    # Never blocks graphical.target.
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

    # After sleep only.
    systemd.services.bluetooth-controller-resume = {
      description = "Reconnect Bluetooth controllers after resume";
      after = [ "suspend.target" "hibernate.target" "hybrid-sleep.target" ];
      wantedBy = [ "suspend.target" "hibernate.target" "hybrid-sleep.target" ];

      serviceConfig = {
        Type = "oneshot";
        ExecStartPre = "${pkgs.coreutils}/bin/sleep 3";
        ExecStart = pkgs.writeShellScript "bt-resume" ''
          # Dormant bluetoothd stays asleep.
          ${pkgs.systemd}/bin/systemctl is-active -q bluetooth.service || exit 0
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
      kernelModules = [
        "uinput"
        "hid-generic"
        "hid-sony"
        "hid-microsoft"
        "hid-nintendo"
      ]
      # Older kernels fail modules-load.
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
    };

    users.groups.input = { };
  };

  geforceNow =
    let
      # Driver mismatch kills Vulkan decode.
      install = pkgs.writeShellScript "geforce-now-install" ''
        flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
        flatpak remote-add --if-not-exists geforcenow https://international.download.nvidia.com/GFNLinux/flatpak/geforcenow.flatpakrepo
        flatpak install --noninteractive --or-update geforcenow com.nvidia.geforcenow

        ver=$(sed -n 's/.*Kernel Module *\([0-9][0-9.]*\).*/\1/p' /proc/driver/nvidia/version 2>/dev/null | tr . -)
        if [ -n "$ver" ]; then
          flatpak install --noninteractive --or-update flathub org.freedesktop.Platform.GL.nvidia-$ver
        fi
        flatpak uninstall --noninteractive --unused
      '';

      unit = {
        path = [ pkgs.flatpak pkgs.gnused ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${install}";
          Nice = 19;
          IOSchedulingClass = "idle";
        };
      };

      focusPath = lib.makeBinPath (with pkgs; [
        coreutils
        gnugrep
        gawk
        nftables
        systemd
        util-linux
      ]);

      # Any uid's gfn.slice scope tree.
      cgGlob = "/sys/fs/cgroup/user.slice/user-*.slice/user@*.service/app.slice/gfn.slice";

      focusStart = pkgs.writeShellScript "gfn-focus-start" ''
        set -u
        export PATH=${focusPath}

        # Same tuning as local games.
        systemctl start nixly-gametune.service || true

        # Background work pauses.
        for u in nixlyos-stage.timer nixlyos-stage.service \
                 nixlyos-autoupdate.timer \
                 htpc-prewarm.timer htpc-prewarm.service; do
          systemctl stop "$u" 2>/dev/null || true
        done

        # Scope appears after flatpak starts.
        cg=""
        for _ in $(seq 30); do
          cg=$(ls -d ${cgGlob} 2>/dev/null | head -1)
          [ -n "$cg" ] && break
          sleep 1
        done
        [ -n "$cg" ] || exit 0

        # EF on every GFN packet.
        rel=''${cg#/sys/fs/cgroup/}
        level=$(echo "$rel" | awk -F/ '{print NF}')
        nft add table inet gfn-live
        nft add chain inet gfn-live out '{ type route hook output priority mangle; policy accept; }'
        nft add rule inet gfn-live out socket cgroupv2 level "$level" \"$rel\" ip dscp set ef
        nft add rule inet gfn-live out socket cgroupv2 level "$level" \"$rel\" ip6 dscp set ef

        # Pids live in the scope.
        procs() { cat "$cg"/cgroup.procs "$cg"/*/cgroup.procs 2>/dev/null; }

        # Empty cgroup ends the stream.
        applied=""
        empty=0
        while :; do
          list=$(procs)
          if [ -z "$list" ]; then
            empty=$(( empty + 1 ))
            [ "$empty" -ge 3 ] && break
          else
            empty=0
            for pid in $list; do
              case " $applied " in *" $pid "*) continue ;; esac
              echo -900 > "/proc/$pid/oom_score_adj" 2>/dev/null || true
              ionice -c 1 -n 0 -p "$pid" 2>/dev/null || true
              applied="$applied $pid"
            done
          fi
          sleep 2
        done
      '';

      focusStop = pkgs.writeShellScript "gfn-focus-stop" ''
        set -u
        export PATH=${focusPath}

        nft delete table inet gfn-live 2>/dev/null || true

        for u in nixlyos-stage.timer nixlyos-autoupdate.timer htpc-prewarm.timer; do
          systemctl start "$u" 2>/dev/null || true
        done

        systemctl stop nixly-gametune.service || true
      '';

      # Only supported way to start GFN.
      launcher = pkgs.writeShellScriptBin "nixly-gfn" ''
        set -u
        SYSTEMCTL=${pkgs.systemd}/bin/systemctl
        RUN=${pkgs.systemd}/bin/systemd-run
        APP="${pkgs.flatpak}/bin/flatpak run com.nvidia.geforcenow --password-store=basic"

        "$SYSTEMCTL" start --no-block gfn-focus.service 2>/dev/null || true
        # Guide menu never waits.
        trap '"$SYSTEMCTL" stop --no-block gfn-focus.service 2>/dev/null || true' EXIT

        # No user bus: stream anyway.
        if "$RUN" --user --scope --quiet --slice=gfn.slice -- true 2>/dev/null; then
          "$RUN" --user --scope --quiet --slice=gfn.slice -- $APP "$@" &
        else
          $APP "$@" &
        fi
        pid=$!
        trap 'kill -TERM $pid 2>/dev/null' TERM INT
        wait $pid
      '';

      # Icon comes from the flatpak.
      desktopItem = pkgs.makeDesktopItem {
        name = "com.nvidia.geforcenow";
        desktopName = "NVIDIA GeForce NOW";
        genericName = "NVIDIA GeForce NOW";
        exec = "${launcher}/bin/nixly-gfn";
        icon = "com.nvidia.geforcenow";
        categories = [ "Network" "Game" ];
      };
    in
    {
      services.flatpak.enable = true;

      # Skipped once installed.
      systemd.services.geforce-now-install = unit // {
        description = "Install NVIDIA GeForce NOW flatpak";
        wantedBy = [ "multi-user.target" ];
        after = [ "network-online.target" "flatpak-system-helper.service" ];
        wants = [ "network-online.target" ];
        unitConfig.ConditionPathExists = "!/var/lib/flatpak/app/com.nvidia.geforcenow";
      };

      systemd.services.geforce-now-update = unit // {
        description = "Update NVIDIA GeForce NOW flatpak";
        unitConfig.ConditionACPower = true;
        after = [ "network-online.target" "flatpak-system-helper.service" ];
        wants = [ "network-online.target" ];
      };

      systemd.timers.geforce-now-update = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "daily";
          RandomizedDelaySec = "30min";
          Persistent = false;
        };
      };

      # Cake's voice tin; outbound only.
      networking.nftables.tables.geforce-now-qos = {
        family = "inet";
        content = ''
          chain postrouting {
            type filter hook postrouting priority mangle; policy accept;
            udp dport 49000-49200 ip dscp set ef
            udp dport 49000-49200 ip6 dscp set ef
          }
        '';
      };

      # Everything else yields to the stream.
      systemd.user.slices.gfn = {
        description = "GeForce NOW stream";
        sliceConfig = {
          CPUWeight = 10000;
          IOWeight = 1000;
          MemoryLow = "4G";
        };
      };

      # Restores even after SIGKILL.
      systemd.services.gfn-focus = {
        description = "Low-latency tuning while GeForce NOW streams";
        serviceConfig = {
          Type = "simple";
          ExecStart = "${focusStart}";
          ExecStopPost = "${focusStop}";
          Restart = "no";
          RuntimeDirectory = "gfn-focus";
          RuntimeDirectoryPreserve = "yes";
        };
      };

      security.polkit.extraConfig = ''
        polkit.addRule(function(action, subject) {
          if (action.id == "org.freedesktop.systemd1.manage-units" &&
              subject.isInGroup("gamemode")) {
            var unit = action.lookup("unit");
            if (unit == "gfn-focus.service") {
              return polkit.Result.YES;
            }
          }
        });
      '';

      environment.systemPackages = [ launcher ];

      # Replaces NVIDIA's own entry.
      home-manager.sharedModules = [
        {
          xdg.dataFile."applications/com.nvidia.geforcenow.desktop".source =
            "${desktopItem}/share/applications/com.nvidia.geforcenow.desktop";
        }
      ];

      # Edge picked from client subnet.
      systemd.network.netdevs."10-gfndns" = {
        netdevConfig = {
          Name = "gfndns";
          Kind = "dummy";
        };
      };

      systemd.network.networks."10-gfndns" = {
        matchConfig.Name = "gfndns";
        networkConfig = {
          DNS = [ "8.8.8.8" "8.8.4.4" ];
          DNSOverTLS = false;
          DNSSEC = false;
          LinkLocalAddressing = "no";
          ConfigureWithoutCarrier = true;
        };
        # Routing domains, never search.
        domains = [
          "~nvidia.com"
          "~nvidiagrid.net"
          "~geforcenow.com"
        ];
        linkConfig.ActivationPolicy = "always-up";
      };
    };

  # Root half of game mode.
  gametune = {
    environment.systemPackages = [ pkgs.nixly-gametune ];

    systemd.services.nixly-gametune = {
      description = "Low-latency tuning while a game is running";
      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.nixly-gametune}/bin/nixly-gametune daemon";
        Restart = "no";
        RuntimeDirectory = "nixly-gametune";
        RuntimeDirectoryPreserve = "yes";
      };
    };

    # Game PID is the instance.
    systemd.services."nixly-gameprio@" = {
      description = "OOM/VRAM protection for game PID %i";
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.nixly-gametune}/bin/nixly-gametune protect %i";
        ExecStop = "${pkgs.nixly-gametune}/bin/nixly-gametune unprotect %i";
        RuntimeDirectory = "nixly-gametune";
        RuntimeDirectoryPreserve = "yes";
      };
    };

    # Lifts the factory power cap.
    systemd.services.nixly-gpumax = {
      description = "NVIDIA power-limit ceiling at boot";
      wantedBy = [ "multi-user.target" ];
      unitConfig.ConditionPathExists = "/sys/module/nvidia";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.nixly-gametune}/bin/nixly-gametune gpumax";
      };
    };

    security.polkit.extraConfig = ''
      polkit.addRule(function(action, subject) {
        if (action.id == "org.freedesktop.systemd1.manage-units" &&
            subject.isInGroup("gamemode")) {
          var unit = action.lookup("unit");
          if (unit && (unit == "nixly-gametune.service" ||
              unit.indexOf("nixly-gameprio@") == 0)) {
            return polkit.Result.YES;
          }
        }
      });
    '';
  };

  # Full priority for nix run.
  boost = {
    environment.systemPackages = [ pkgs.nixly-boost ];
  };

  prewarm =
    let
      # Two last played games only.
      games = pkgs.writeShellScript "nixly-prewarm-games" ''
        set -u
        VMTOUCH=${pkgs.vmtouch}/bin/vmtouch

        warm() {
          [ -e "$1" ] && "$VMTOUCH" -t -q -m 512M "$1" 2>/dev/null || true
        }

        S="$HOME/.local/share/Steam"
        [ -d "$S" ] || S="$HOME/.steam/steam"
        [ -d "$S" ] || exit 0

        # Every Steam library folder.
        libs="$S"
        vdf="$S/steamapps/libraryfolders.vdf"
        if [ -f "$vdf" ]; then
          extra=$(${pkgs.gnugrep}/bin/grep -oP '"path"\s+"\K[^"]+' "$vdf" 2>/dev/null || true)
          libs=$(printf '%s\n%s\n' "$libs" "$extra" | ${pkgs.coreutils}/bin/sort -u)
        fi

        # Two most recently played.
        manifests() {
          for lib in $libs; do
            for m in "$lib"/steamapps/appmanifest_*.acf; do
              [ -f "$m" ] || continue
              ${pkgs.gawk}/bin/awk -F'"' -v lib="$lib" '
                /"installdir"/  { d = $4 }
                /"LastPlayed"/  { p = $4 }
                END {
                  if (d != "" && d !~ /^(Proton|SteamLinuxRuntime|Steamworks)/)
                    printf "%d|%s/steamapps/common/%s\n", p, lib, d
                }' "$m"
            done
          done
        }

        played=$(manifests | ${pkgs.coreutils}/bin/sort -t'|' -k1,1 -rn \
          | ${pkgs.gawk}/bin/awk -F'|' '$1 > 0 { print $2 }' | ${pkgs.coreutils}/bin/head -2)
        # A pipe would swallow exit.
        while IFS= read -r d; do
          [ -n "$d" ] || continue
          ${prewarmGate} || exit 0
          warm "$d"
        done <<< "$played"
      '';

      # Launch chain into page cache.
      pagecache = pkgs.writeShellScript "nixly-pagecache" ''
        set -u
        VMTOUCH=${pkgs.vmtouch}/bin/vmtouch

        # Huge paks stream anyway.
        warm() {
          [ -e "$1" ] && "$VMTOUCH" -t -q -m 512M "$1" 2>/dev/null || true
        }

        # Client, runtime and Proton.
        S="$HOME/.local/share/Steam"
        [ -d "$S" ] || S="$HOME/.steam/steam"
        if [ -d "$S" ]; then
          warm "$S/steamrt64"
          warm "$S/steamrt32"
          warm "$S/linux32"
          warm "$S/linux64"
          warm "$S/config"
          for d in "$S"/steamapps/common/SteamLinuxRuntime*; do
            warm "$d"
          done
          # The Proton autoconfig picks.
          warm "${protonNixlyos}"
          for d in "$S"/steamapps/common/Proton*; do
            warm "$d"
          done
          warm "$S/steamapps/shadercache"
        fi
        warm "$HOME/.cache/mesa_shader_cache"
        warm "$HOME/.cache/mesa_shader_cache_db"
        warm "$HOME/.cache/nvidia/GLCache"
        warm "$HOME/.nv/GLCache"
      '';

      # After 10 idle minutes with Steam.
      activity = pkgs.writeShellApplication {
        name = "nixly-activity-prewarm";
        runtimeInputs = with pkgs; [ coreutils procps systemd ];
        text = ''
          need=600
          step=10
          while :; do
            # Never starts Steam itself.
            if ! pgrep -x steam >/dev/null 2>&1; then
              sleep 60
              continue
            fi
            if [ ! -r /dev/input/mice ]; then
              # Idleness is unmeasurable.
              sleep 600
              continue
            fi
            # Any byte means motion.
            idle=0
            while [ "$idle" -lt "$need" ]; do
              if timeout "$step" head -c1 /dev/input/mice >/dev/null 2>&1; then
                idle=0
              else
                idle=$((idle + step))
              fi
            done
            pgrep -x steam >/dev/null 2>&1 || continue
            systemctl --user start nixly-prewarm-games.service &
            spid=$!
            aborted=0
            while kill -0 "$spid" 2>/dev/null; do
              if timeout "$step" head -c1 /dev/input/mice >/dev/null 2>&1; then
                aborted=1
                systemctl --user stop nixly-prewarm-games.service
                break
              fi
            done
            wait "$spid" 2>/dev/null || true
            # Done unless aborted.
            if [ "$aborted" -eq 0 ]; then
              exit 0
            fi
          done
        '';
      };
    in
    {
      # fossilize_replay needs steam-run.
      environment.systemPackages = [
        pkgs.nixly-prewarm
        activity
        pkgs.steam-run
        pkgs.vmtouch
      ];

      systemd.user.services.nixly-prewarm-games = {
        description = "Preload Steam launch chain and the two last played games";
        serviceConfig = {
          Type = "oneshot";
          ExecCondition = "${prewarmGate}";
          ExecStart = [ "${pagecache}" "${games}" ];
          IOSchedulingClass = "idle";
          CPUSchedulingPolicy = "idle";
          Nice = 19;
          # Reclaims its own pages first.
          MemoryHigh = "25%";
        };
      };

      # Stops itself when games start.
      systemd.user.services.nixly-prewarm = {
        description = "nixlytile Steam shader prewarm";
        serviceConfig = {
          Type = "oneshot";
          ExecCondition = "${prewarmGate}";
          ExecStart = "${pkgs.nixly-prewarm}/bin/nixly-prewarm run";
          Nice = 19;
          IOSchedulingClass = "idle";
          CPUSchedulingPolicy = "batch";
        };
        # Vendor Vulkan ICDs.
        path = [ "/run/current-system/sw" ];
      };

      # Replays caches as they land.
      systemd.user.services.nixly-prewarm-watch = {
        description = "nixlytile Steam shader prewarm install watcher";
        wantedBy = [ "default.target" ];
        serviceConfig = {
          ExecStart = "${pkgs.nixly-prewarm}/bin/nixly-prewarm watch";
          Restart = "on-failure";
          RestartSec = 30;
          Nice = 19;
          IOSchedulingClass = "idle";
          CPUSchedulingPolicy = "batch";
        };
        path = [ "/run/current-system/sw" ];
      };
    };

  # Polls the NFS share.
  romPlaylists =
    let
      retroarch = lib.findFirst (p: (p.meta.mainProgram or null) == "retroarch") null
        config.environment.systemPackages;
      playlists = pkgs.rom-playlists.override { inherit retroarch; };
    in
    {
      home-manager.users.${nixlyUser} = { ... }: lib.mkIf (retroarch != null) {
        home.packages = [ playlists ];

        systemd.user.services.rom-playlists = {
          Unit.Description = "Generate RetroArch playlists from NFS ROMs";
          Service = {
            Type = "oneshot";
            ExecStart = "${playlists}/bin/rom-playlists";
          };
        };

        systemd.user.timers.rom-playlists = {
          Unit.Description = "Periodic RetroArch playlist re-scan";
          Install.WantedBy = [ "timers.target" ];
          Timer = {
            # After session and network.
            OnStartupSec = "45s";
            OnUnitActiveSec = "30min";
          };
        };
      };
    };

  # Served to tablets over tailnet.
  dcspit = {
    networking.hosts."127.0.0.1" = [ "dcspit.local" ];
  };

  # 4K fullscreen emulator configs.
  emulatorConfigs =
    { lib, ... }:

    {
      home.activation.emulatorConfigs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''

        # Dolphin (GameCube / Wii)
        mkdir -p "$HOME/.config/dolphin-emu"

        cat > "$HOME/.config/dolphin-emu/GFX.ini" << 'DOLPHINGFX'
    [Settings]
    # Matches the display.
    EFBScale = 0
    AspectRatio = 0
    ShaderCompilationMode = 2
    WaitForShadersBeforeStarting = True
    MSAA = 0
    SSAA = False
    ShowFPS = False
    LogRenderTimeToFile = False

    [Enhancements]
    ForceFiltering = True
    MaxAnisotropy = 4
    ForceTrueColor = True
    DisableCopyFilter = True
    ArbitraryMipmapDetection = True

    [Hacks]
    EFBAccessEnable = True
    EFBToTextureEnable = True
    XFBToTextureEnable = True
    EFBScaledCopy = True
    SkipDuplicateXFBs = True
    ApproximateLogicOp = True

    [Hardware]
    VSync = True
    DOLPHINGFX

        cat > "$HOME/.config/dolphin-emu/Dolphin.ini" << 'DOLPHININI'
    [Display]
    Fullscreen = True
    RenderToMain = True
    KeepWindowOnTop = False

    [Core]
    SkipIdle = True
    SyncOnSkipIdle = True
    CPUThread = True
    GPUDeterminismMode = auto
    EmulationSpeed = 1.00
    DOLPHININI


        # mGBA (Game Boy / GBC / GBA)
        mkdir -p "$HOME/.config/mgba"

        cat > "$HOME/.config/mgba/config.ini" << 'MGBAINI'
    [ports.qt]
    fullscreen=1
    fpsTarget=60
    audioSync=1
    videoSync=1
    lockAspectRatio=1
    volume=256
    scaleMultiplier=16
    resampleVideo=0
    suspendScreensaver=1
    pauseOnFocusLost=0
    MGBAINI


        # PPSSPP (PSP)
        mkdir -p "$HOME/.config/ppsspp/PSP/SYSTEM"

        cat > "$HOME/.config/ppsspp/PSP/SYSTEM/ppsspp.ini" << 'PPSSPPINI'
    [General]
    FirstRun = False
    AutoRun = True
    IgnoreBadMemAccess = True
    CheckForNewVersion = False
    DiscordRichPresence = False
    UISound = False
    EnableCheats = False
    EnablePlugins = True

    [Graphics]
    GraphicsBackend = 0 (OPENGL)
    UseGeometryShader = False
    SkipBufferEffects = False
    SoftwareRenderer = False
    HardwareTransform = True
    SoftwareSkinning = True
    TextureFiltering = 1
    InternalResolution = 10
    HighQualityDepth = 1
    FrameSkip = 0
    AutoFrameSkip = False
    AnisotropyLevel = 4
    MultiSampleLevel = 0
    FullScreen = True
    BufferFiltering = 1
    ImmersiveMode = True
    ReplaceTextures = True
    TexScalingLevel = 1
    VSync = True
    SplineBezierQuality = 2
    ShaderCache = True
    UberShaderVertex = True
    UberShaderFragment = True
    MultiThreading = True
    InflightFrames = 3
    DisplayCropTo16x9 = True

    [Sound]
    Enable = True
    ExtraAudioBuffering = False
    AudioBufferSize = 256
    GameVolume = 100

    [Control]
    HapticFeedback = False
    PPSSPPINI


        # PCSX2 (PlayStation 2)
        mkdir -p "$HOME/.config/PCSX2/inis"

        cat > "$HOME/.config/PCSX2/inis/PCSX2.ini" << 'PCSX2INI'
    [UI]
    StartFullscreen = true
    ConfirmShutdown = false

    [EmuCore/GS]
    upscale_multiplier = 6
    MaxAnisotropy = 4
    linear_present_mode = 1
    TextureFiltering = 2
    TriFilter = 1
    dithering_ps2 = 2
    accurate_blending_unit = 1
    texture_preloading = 2
    HWDownloadMode = 0
    conservative_framebuffer = 1
    pcrtc_offsets = 1
    pcrtc_antiblur = 1
    mipmap_hw = 0
    Renderer = -1

    [EmuCore/Speedhacks]
    EECycleRate = 0
    EECycleSkip = 0
    fastCDVD = 0
    IntcStat = 1
    WaitLoop = 1
    vuFlagHack = 1
    vu1Instant = 1
    PCSX2INI


        # Flycast (Dreamcast)
        mkdir -p "$HOME/.config/flycast"

        cat > "$HOME/.config/flycast/emu.cfg" << 'FLYCASTCFG'
    [config]
    Fullscreen = yes
    Section = console

    [window]
    fullscreen = yes
    width = 3840
    height = 2160

    [pvr]
    rend.Resolution = 3840
    rend.WideScreen = 0
    rend.Clipping = 1
    rend.TextureUpscale = 4
    rend.MaxFilteredTextureSize = 256
    ta.skip = 0
    rend.AnisotropicFiltering = 4
    rend.PerPixel = 1

    [audio]
    backend = auto
    LimitFPS = 1

    [input]
    maple_sdl_joystick_0 = 0
    FLYCASTCFG


        # Blastem (Genesis / Mega Drive / SMS)
        mkdir -p "$HOME/.config/blastem"

        cat > "$HOME/.config/blastem/blastem.cfg" << 'BLASTEMCFG'
    video {
    	fullscreen on
    	gl on
    	vsync on
    	scaling linear
    	scanlines off
    }
    BLASTEMCFG


        # Stella (Atari 2600)
        mkdir -p "$HOME/.config/stella"

        cat > "$HOME/.config/stella/stellarc" << 'STELLARC'
    fullscreen = 1
    vsync = 1
    video = opengl
    tia.zoom = 8
    tia.inter = 0
    tia.fsfill = 0
    center = 1
    sound = 1
    volume = 100
    joydeadzone = 6
    STELLARC


        # Xenia Canary (Xbox 360)
        mkdir -p "$HOME/.config/xenia"

        cat > "$HOME/.config/xenia/xenia-canary.config.toml" << 'XENIACFG'
    [Display]
    fullscreen = true
    present_letterbox = true

    [GPU]
    draw_resolution_scale_x = 3
    draw_resolution_scale_y = 3
    gpu = "vulkan"
    vsync = true

    [GPU.Vulkan]
    vulkan_allow_present_mode_mailbox = true
    vulkan_allow_present_mode_immediate = false
    vulkan_allow_present_mode_fifo_relaxed = true

    [HID]
    hid = "sdl"

    [General]
    license_mask = -1

    [Canary]
    internal_display_resolution = 12
    XENIACFG


        # melonDS (Nintendo DS)
        mkdir -p "$HOME/.config/melonDS"

        cat > "$HOME/.config/melonDS/melonDS.toml" << 'MELONDSTOML'
    [Instance0]
    Window.Fullscreen = true

    [3D]
    Renderer = 1
    GL_ScaleFactor = 8
    GL_BetterPolygons = true
    GL_HiresCoordinates = true

    [Screen]
    ScreenLayout = 0
    ScreenSizing = 3
    IntegerScaling = false
    ScreenFilter = true
    ScreenAspectTop = 0
    ScreenAspectBot = 0

    [Audio]
    Volume = 256
    MELONDSTOML


        # Azahar / Citra (Nintendo 3DS)
        mkdir -p "$HOME/.config/azahar/config"

        cat > "$HOME/.config/azahar/config/qt-config.ini" << 'AZAHARINI'
    [Renderer]
    use_hw_renderer = true
    use_hw_renderer\default = false
    use_hw_shader = true
    use_hw_shader\default = false
    resolution_factor = 4
    resolution_factor\default = false
    use_shader_jit = true
    use_shader_jit\default = false
    use_vsync_new = true
    use_vsync_new\default = false
    texture_filter = 0
    texture_filter\default = true

    [Layout]
    layout_option = 0
    layout_option\default = true
    fullscreen = true
    fullscreen\default = false

    [Audio]
    output_type = auto
    output_type\default = true
    volume = 1
    AZAHARINI


        # Cemu (Wii U)
        mkdir -p "$HOME/.config/Cemu"

        cat > "$HOME/.config/Cemu/settings.xml" << 'CEMUXML'
    <?xml version="1.0" encoding="utf-8"?>
    <content>
    	<Graphic>
    		<api>1</api>
    		<VSync>0</VSync>
    		<GX2DrawdoneSync>true</GX2DrawdoneSync>
    		<UpscaleFilter>1</UpscaleFilter>
    		<DownscaleFilter>0</DownscaleFilter>
    		<FullscreenScaling>0</FullscreenScaling>
    		<AsyncCompile>true</AsyncCompile>
    		<Overlay>
    			<Position>0</Position>
    			<FPS>false</FPS>
    		</Overlay>
    	</Graphic>
    	<Audio>
    		<api>0</api>
    		<delay>2</delay>
    		<TVVolume>100</TVVolume>
    		<PadVolume>0</PadVolume>
    		<TVChannels>1</TVChannels>
    	</Audio>
    	<Fullscreen>true</Fullscreen>
    </content>
    CEMUXML


        # RPCS3 (PlayStation 3)
        mkdir -p "$HOME/.config/rpcs3"

        cat > "$HOME/.config/rpcs3/config.yml" << 'RPCS3YML'
    Video:
      Renderer: Vulkan
      Resolution: 1280x720
      Aspect ratio: "16:9"
      Frame limit: Auto
      MSAA: Disabled
      Shader Mode: Async Shader Recompiler
      Write Color Buffers: false
      Write Depth Buffer: false
      Read Color Buffers: false
      Read Depth Buffer: false
      VSync: true
      Stretch To Display Area: false
      Resolution Scale: 300
      Resolution Scale Threshold: 16
      Anisotropic Filter Override: 16
      Shader Precision: High

    Audio:
      Renderer: Cubeb
      Audio Format: Automatic
      Master Volume: 100
      Enable Buffering: true
      Desired Audio Buffer Duration: 100

    Input/Output:
      Keyboard: "Null"
      Mouse: "Null"
      Camera: "Null"
      Camera type: Unknown
      Move: "Null"
      Buzz emulated controller: "Null"
      Turntable emulated controller: "Null"
      GHLtar emulated controller: "Null"
      Pad handler: SDL

    Miscellaneous:
      Start Fullscreen: true
      Exit RPCS3 when process finishes: true
      Automatically start games after boot: true
      Show shader compilation hint: false
    RPCS3YML


        # Others default sanely via SDL2.

      '';
    }
  ;

  emulators = {
    home-manager.sharedModules = [ emulatorConfigs ];
  };
in
{
  # Gaming is x86 only.
  imports = lib.optionals (hwData.platform.arch == "x86_64") [
    tools
    controllers
    steam
    geforceNow
    boost
    gametune
    prewarm
    romPlaylists
    dcspit
    emulators
  ];
}
