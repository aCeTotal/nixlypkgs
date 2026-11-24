{ config, lib, pkgs, inputs, hwData, nixlyUser, ... }:

let
  isHtpc = config.nixlyos.mode == "htpc";
  isArm = hwData.platform.arch == "aarch64";
  bootMode = hwData.platform.bootMode or "efi";
  # Battery policy, desktops only.
  laptop = hwData.dmi.isLaptop && config.nixlyos.mode == "desktop";
  hw = hwData.resources;

  mode = {
    options.nixlyos.mode = lib.mkOption {
      type = lib.types.enum [ "desktop" "htpc" "server" ];
      default = "desktop";
      description = "NixlyOS machine role; the profile sets it.";
    };

    config = {
      assertions = [{
        assertion = !(isHtpc && isArm);
        message = "nixlyos.mode = \"htpc\" er x86-only (Steam/GFN); denne ARM-maskinen må bruke \"desktop\".";
      }];

      # Read by nixlyos-panel adopt.
      environment.etc."nixlyos-mode".text = config.nixlyos.mode;
    };
  };

  identity = {
    # distroId stays nixos for tools.
    system.nixos = {
      distroName = "NixlyOS";
      vendorName = "NixlyOS";
      extraOSReleaseArgs = {
        CPE_NAME = "cpe:/o:nixlyos:nixlyos:${config.system.nixos.release}";
        DEFAULT_HOSTNAME = "nixlyos";
        HOME_URL = "https://github.com/aCeTotal/nixlypkgs";
        VENDOR_URL = "https://github.com/aCeTotal/nixlypkgs";
        DOCUMENTATION_URL = "https://github.com/aCeTotal/nixlypkgs";
        SUPPORT_URL = "https://github.com/aCeTotal/nixlypkgs";
        BUG_REPORT_URL = "https://github.com/aCeTotal/nixlypkgs/issues";
      };
    };
  };

  boot = {
    boot = {
      # EFI, U-Boot SBCs or legacy BIOS.
      loader =
        if bootMode == "extlinux" then {
          generic-extlinux-compatible.enable = true;
          grub.enable = false;
          timeout = 0;
        } else if bootMode == "bios" then {
          grub.enable = true;
          grub.device =
            if (hwData.platform.bootDevice or null) != null then hwData.platform.bootDevice else "nodev";
          grub.configurationLimit = 2;
          timeout = 0;
        } else {
          efi = {
            canTouchEfiVariables = true;
            efiSysMountPoint = "/boot";
          };

          systemd-boot.enable = true;
          systemd-boot.configurationLimit = 2;
          # Editing params grants root.
          systemd-boot.editor = false;
          timeout = 0;
        };

      initrd.systemd.enable = true;
      # Root comes up without waiting.
      initrd.availableKernelModules = [ "nvme" "nvme_core" ];
      initrd.kernelModules = [ "btrfs" ];
      consoleLogLevel = 3;
      # Purging on-disk /tmp cost 2 s.
      tmp.useTmpfs = true;

      plymouth.enable = false;

      supportedFilesystems = [ "ext4" "btrfs" "vfat" "ntfs3" ];

      kernelParams = [
        "quiet"
        "loglevel=3"
        "rd.udev.log_level=3"
        "udev.log_priority=3"
        "systemd.show_status=false"
        "rd.systemd.show_status=false"
      ]
      ++ lib.optional (!isArm) "8250.nr_uarts=0"
      ++ lib.optional (!isArm) "random.trust_cpu=on"
      ++ [
        "nowatchdog"
      ]
      ++ lib.optionals (!isArm) [
        "nmi_watchdog=0"
        # No untrusted users on HTPC.
        (if isHtpc then "mitigations=off" else "mitigations=auto")
        (if isHtpc then "iommu.strict=0" else "iommu.strict=1")
        "split_lock_detect=off"
        # Mains machines keep links awake.
        (if laptop
        then "nvme_core.default_ps_max_latency_us=100000"
        else "nvme_core.default_ps_max_latency_us=0")
        (if laptop then "pcie_aspm.policy=powersave" else "pcie_aspm.policy=performance")
      ]
      ++ [
        # Audit taxes every syscall.
        "audit=0"
      ];

      blacklistedKernelModules = lib.optionals (!isArm) [ "8250_pci" ];

      # HTPC codec never sleeps.
      extraModprobeConfig =
        if isHtpc then ''
          options snd_hda_intel power_save=0 power_save_controller=N
        '' else
          lib.optionalString laptop ''
            options snd_hda_intel power_save=1 power_save_controller=Y
            options i915 enable_psr=1
          '';

      kernel.sysctl = {
        # Emergency sync, remount and reboot.
        "kernel.sysrq" = 176;
        "kernel.kptr_restrict" = 2;
        "kernel.dmesg_restrict" = 1;
        "kernel.unprivileged_bpf_disabled" = 1;
        "fs.protected_hardlinks" = 1;
        "fs.protected_symlinks" = 1;
        "fs.protected_fifos" = 2;
        "fs.protected_regular" = 2;

        "net.ipv4.conf.all.rp_filter" = 1;
        "net.ipv4.conf.default.rp_filter" = 1;
        "net.ipv4.conf.all.accept_redirects" = 0;
        "net.ipv4.conf.default.accept_redirects" = 0;
        "net.ipv6.conf.all.accept_redirects" = 0;
        "net.ipv6.conf.default.accept_redirects" = 0;
        "net.ipv4.conf.all.send_redirects" = 0;
        "net.ipv4.conf.default.send_redirects" = 0;
        "net.ipv4.conf.all.accept_source_route" = 0;
        "net.ipv6.conf.all.accept_source_route" = 0;
        "net.ipv4.icmp_echo_ignore_broadcasts" = 1;

        "kernel.yama.ptrace_scope" = 1;
        "fs.suid_dumpable" = 0;
        "kernel.kexec_load_disabled" = 1;
        "kernel.perf_event_paranoid" = 2;
        # 2 slows scx_lavd.
        "net.core.bpf_jit_harden" = 1;
        "dev.tty.ldisc_autoload" = 0;
        "vm.unprivileged_userfaultfd" = 0;
        "net.ipv4.tcp_syncookies" = 1;

        # Steam Deck default.
        "vm.max_map_count" = 2147483642;
      };
    };

    services.fstrim.enable = true;

    # Fewer metadata writes.
    fileSystems."/".options = lib.mkIf (config.fileSystems."/".fsType == "ext4")
      [ "noatime" "lazytime" "commit=120" ];

    # Userland owns the backlight.
    systemd.services."systemd-backlight@backlight:intel_backlight".enable = lib.mkForce false;
  };

  # Kernel 7 keeps initramfs resident.
  initrd =
    let
      pin = "/run/nixly-initrd";
    in
    {
      boot.initrd.systemd.services.nixly-initrd-pin = {
        description = "Carry the initramfs across switch-root";
        unitConfig.DefaultDependencies = false;
        after = [ "initrd-switch-root.target" ];
        before = [ "initrd-switch-root.service" ];
        wantedBy = [ "initrd-switch-root.service" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = [ "/bin/mkdir -p ${pin}" "/bin/mount --bind / ${pin}" ];
        };
      };

      systemd.services.nixly-initrd-free = {
        description = "Free the initramfs";
        wantedBy = [ "sysinit.target" ];
        unitConfig = {
          DefaultDependencies = false;
          ConditionPathIsMountPoint = pin;
        };
        path = [ pkgs.util-linux ];
        serviceConfig.Type = "oneshot";
        script = ''
          case $(stat -f -c %T ${pin}) in ramfs|tmpfs) ;; *) exit 1 ;; esac
          find ${pin} -mindepth 1 -maxdepth 1 -exec rm -rf --one-file-system {} +
          umount ${pin}
          rmdir ${pin}
        '';
      };
    };

  nix =
    let
      caches = inputs.nixlypkgs.lib.nixlyos.caches;

      # Daily cleanup after an idle hour.
      gcWatch = pkgs.writeShellApplication {
        name = "nixly-gc-watch";
        runtimeInputs = with pkgs; [ coreutils findutils procps systemd util-linux ];
        text = ''
          stamp=/var/lib/nixly-gc-watch/last
          while :; do
            now=$(date +%s)
            if [ -f "$stamp" ]; then
              last=$(stat -c %Y "$stamp")
              left=$(( 86400 - (now - last) ))
              if [ "$left" -gt 0 ]; then
                sleep "$left"
                continue
              fi
            fi
            if [ ! -r /dev/input/mice ]; then
              sleep 3600
              continue
            fi
            # Any byte means motion.
            idle=0
            while [ "$idle" -lt 3600 ]; do
              if timeout 60 head -c1 /dev/input/mice >/dev/null 2>&1; then
                idle=0
              else
                idle=$((idle + 60))
              fi
            done
            if systemctl is-active -q nixly-gametune.service \
               || ! systemd-ac-power \
               || pgrep -x wineserver >/dev/null 2>&1 \
               || pgrep -x gamescope >/dev/null 2>&1 \
               || pgrep -x retroarch >/dev/null 2>&1 \
               || pgrep -x reaper >/dev/null 2>&1; then
              sleep 600
              continue
            fi
            systemctl start nix-gc.service
            # Age-trim the journal.
            journalctl --vacuum-time=14d >/dev/null 2>&1 || true
            # Drop old crash dumps.
            find /var/lib/systemd/coredump -type f -mtime +7 -delete 2>/dev/null || true
            # Drop stale thumbnails.
            find /home/*/.cache/thumbnails -type f -mtime +30 -delete 2>/dev/null || true
            # Trashinfo mtime marks deletion.
            for t in /home/*/.local/share/Trash; do
              [ -d "$t/info" ] || continue
              find "$t/info" -name '*.trashinfo' -mtime +30 2>/dev/null \
              | while IFS= read -r info; do
                name=$(basename "$info" .trashinfo)
                rm -rf -- "$t/files/$name" "$info" 2>/dev/null || true
              done
            done
            # Trim right after GC.
            fstrim -a >/dev/null 2>&1 || true
            touch "$stamp"
          done
        '';
      };

      # Only daemon threads left: idle.
      daemonIdle = pkgs.writeShellApplication {
        name = "nixly-nix-daemon-idle";
        runtimeInputs = with pkgs; [ gawk systemd ];
        text = ''
          cg=/sys/fs/cgroup/system.slice/nix-daemon.service
          grace=60
          step=10
          pid=$(systemctl show -p MainPID --value nix-daemon.service)
          idle=0
          while sleep "$step"; do
            threads=$(awk '/^Threads:/ { print $2 }' "/proc/$pid/status" 2>/dev/null) || exit 0
            if [ "$(< "$cg/pids.current")" -gt "$threads" ]; then
              idle=0
              continue
            fi
            idle=$(( idle + step ))
            [ "$idle" -lt "$grace" ] || exec systemctl stop --no-block nix-daemon.service
          done
        '';
      };

      idleService = {
        Slice = "background.slice";
        CPUSchedulingPolicy = "idle";
        IOSchedulingClass = "idle";
        Nice = 19;
      };
    in
    {
      nix = {
        package = pkgs.nixVersions.latest;

        settings = {
          sandbox = true;
          accept-flake-config = false;
          # detect-hw dirties every eval.
          warn-dirty = false;
          experimental-features = [ "nix-command" "flakes" ];
          keep-outputs = true;
          keep-derivations = true;
          builders-use-substitutes = true;
          # One job per 8 GiB.
          max-jobs = hw.maxJobs;
          cores = hw.buildCores;
          http-connections = 50;
          # Dead substituters never stall.
          connect-timeout = 5;
          fallback = true;
          min-free = 2147483648;
          max-free = 6442450944;
          trusted-users = [ "root" "@wheel" ];

          substituters = caches.urls;
          trusted-substituters = caches.urls;
          trusted-public-keys = caches.keys;
        };

        # nixly-gc-watch starts it.
        gc = {
          automatic = false;
          options = "--delete-older-than 3d";
        };

        optimise = {
          automatic = true;
          dates = [ "Sun 05:00" ];
          persistent = false;
        };
      };

      # Rebuilt every time otherwise.
      documentation.nixos.enable = false;

      systemd.services.nixly-gc-watch = {
        description = "Run nix-gc after 60 min mouse idle without a game, max once a day";
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          ExecStart = "${gcWatch}/bin/nixly-gc-watch";
          Restart = "on-failure";
          RestartSec = 60;
          StateDirectory = "nixly-gc-watch";
          Slice = "background.slice";
          Nice = 19;
          IOSchedulingClass = "idle";
        };
      };

      systemd.services.nix-gc = {
        serviceConfig = idleService;
        # Keeps ~/git flakes alive.
        requires = [ "nixly-project-roots.service" ];
        after = [ "nixly-project-roots.service" ];
      };

      systemd.services.nix-optimise = {
        serviceConfig = idleService;
        unitConfig.ConditionACPower = true;
      };

      # Builds die before the desktop.
      systemd.services.nix-daemon = {
        serviceConfig = {
          MemoryAccounting = true;
          MemoryHigh = "80%";
          MemoryMax = "90%";
          Delegate = "memory cpu io";
          OOMScoreAdjust = 500;
          CPUWeight = 20;
          IOWeight = 20;
        };
        # Builds stay off tmpfs.
        environment.TMPDIR = "/nix/tmp";
      };

      # Socket restarts it on demand.
      systemd.services.nixly-nix-daemon-idle = {
        description = "Stop nix-daemon when idle";
        bindsTo = [ "nix-daemon.service" ];
        after = [ "nix-daemon.service" ];
        wantedBy = [ "nix-daemon.service" ];
        serviceConfig = {
          ExecStart = "${daemonIdle}/bin/nixly-nix-daemon-idle";
          Restart = "on-failure";
        };
      };

      systemd.services.nixly-project-roots = {
        description = "GC-root every flake in ~/git";
        serviceConfig = {
          Type = "oneshot";
          User = nixlyUser;
          ExecStart = "${pkgs.nixly-project-roots}/bin/nixly-project-roots";
          Nice = 19;
          CPUSchedulingPolicy = "idle";
          IOSchedulingClass = "idle";
        };
      };

      systemd.tmpfiles.rules = [ "d /nix/tmp 1777 root root -" ];

      # Nightly, never replayed at boot.
      services.fstrim.interval = "Sun 04:00";
      systemd.timers.fstrim.timerConfig.Persistent = false;
      systemd.services.fstrim.unitConfig.ConditionACPower = true;
    };

  users = {
    users.mutableUsers = true;

    users.users.${nixlyUser} = {
      isNormalUser = true;
      description = "Primary user";
      home = "/home/${nixlyUser}";
      shell = pkgs.bashInteractive;
      initialPassword = "nixly";
      extraGroups = [
        "wheel"
        "bluetooth"
        "disk"
        "power"
        "video"
        "audio"
        "render"
        "systemd-journal"
        "dialout"
        "libvirtd"
        "kvm"
        "input"
        "uinput"
        "gamemode"
        # wpa_supplicant control socket.
        "wpa_supplicant"
      ];
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICTkd7+i+h7SK83+dxPNpAknDr17sUt6cIR99SuKj6pf lars.oksendal@gmail.com"
      ];
    };

    users.groups.uinput = { };
    # Polkit and PAM limits key on it.
    users.groups.gamemode = { };
  };

  locale = {
    time.timeZone = "Europe/Oslo";
    # UTC RTC keeps clock sync.
    time.hardwareClockInLocalTime = false;

    i18n.defaultLocale = "en_US.UTF-8";
    i18n.supportedLocales = [
      "en_US.UTF-8/UTF-8"
      "nb_NO.UTF-8/UTF-8"
    ];
    i18n.extraLocaleSettings = {
      LC_ADDRESS = "nb_NO.UTF-8";
      LC_IDENTIFICATION = "nb_NO.UTF-8";
      LC_MEASUREMENT = "nb_NO.UTF-8";
      LC_MONETARY = "nb_NO.UTF-8";
      LC_NAME = "nb_NO.UTF-8";
      LC_NUMERIC = "nb_NO.UTF-8";
      LC_PAPER = "nb_NO.UTF-8";
      LC_TELEPHONE = "nb_NO.UTF-8";
      LC_TIME = "nb_NO.UTF-8";
    };

    console = {
      packages = [ pkgs.terminus_font ];
      font = "${pkgs.terminus_font}/share/consolefonts/ter-i22b.psf.gz";
    };

    services.timesyncd.enable = true;
  };

  services = {
    environment.systemPackages = with pkgs; [
      gcr
      libsecret
      iotop
      htop
      btop
    ];

    programs.neovim.defaultEditor = true;
    programs.mtr.enable = true;
    programs.gnupg.agent = {
      enable = true;
      # ssh-agent stays default.
      enableSSHSupport = false;
    };
    programs.dconf.enable = true;

    services.tumbler.enable = true;
    services.gvfs.enable = true;
    services.udisks2.enable = true;
    services.gnome.gnome-keyring.enable = true;

    # Keyring unlocks at login.
    security.pam.services.sddm.enableGnomeKeyring = true;
    security.pam.services.ly.enableGnomeKeyring = true;
    security.pam.services.login.enableGnomeKeyring = true;

    # IRQs stay off game cores.
    services.irqbalance.enable = true;
    systemd.services.irqbalance.serviceConfig.ExecStart = [
      ""
      (pkgs.writeShellScript "irqbalance-isolated" ''
        set -u
        # getconf is not in coreutils.
        ncpu=$(${pkgs.coreutils}/bin/nproc)
        sibs=$(${pkgs.coreutils}/bin/cat \
          /sys/devices/system/cpu/cpu0/topology/thread_siblings_list 2>/dev/null || echo 0)

        if [ "$ncpu" -lt 8 ]; then
          exec ${pkgs.irqbalance}/bin/irqbalance --foreground
        fi

        # Formats: 0,8 or 0-1.
        expand_sibs() {
          local out="" p c
          IFS=, read -ra parts <<< "$1"
          for p in "''${parts[@]}"; do
            case "$p" in
              *-*) for ((c=''${p%-*}; c<=''${p#*-}; c++)); do out="$out $c"; done ;;
              *)   out="$out $p" ;;
            esac
          done
          printf '%s' "$out"
        }
        allowed=$(expand_sibs "$sibs")

        # Second core absorbs download softirqs.
        for ((c=1; c<ncpu; c++)); do
          case " $allowed " in *" $c "*) continue ;; esac
          sibs2=$(${pkgs.coreutils}/bin/cat \
            "/sys/devices/system/cpu/cpu$c/topology/thread_siblings_list" \
            2>/dev/null || echo "$c")
          allowed="$allowed$(expand_sibs "$sibs2")"
          break
        done

        # Banned CPUs as hex groups.
        ngroups=$(( (ncpu + 31) / 32 ))
        declare -a grp
        for ((i=0; i<ngroups; i++)); do grp[i]=0; done
        for ((c=0; c<ncpu; c++)); do
          case " $allowed " in *" $c "*) continue ;; esac
          gi=$((c / 32)); bit=$((c % 32))
          grp[gi]=$(( ''${grp[gi]} | (1 << bit) ))
        done
        mask=""
        for ((i=ngroups-1; i>=0; i--)); do
          printf -v h "%08x" "''${grp[i]}"
          if [ -z "$mask" ]; then mask="$h"; else mask="$mask,$h"; fi
        done

        export IRQBALANCE_BANNED_CPUS="$mask"
        echo "irqbalance: IRQ-er begrenset til CPU(er) $allowed (banned=$mask)"
        exec ${pkgs.irqbalance}/bin/irqbalance --foreground
      '')
    ];

    # Backs up the kernel OOM.
    services.earlyoom = {
      enable = true;
      enableNotifications = true;
      freeMemThreshold = 5;
      freeSwapThreshold = 10;
      # Matches comm, 15 chars.
      extraArgs = [
        "--prefer"
        "^(Web Content|firefox|brave|electron)$"
        "--avoid"
        "^(sshd|systemd|dbus|nixlytile|nixlyOS|wineserver|wine|retroarch|gamescope)|\\.exe"
      ];
    };

    boot.kernel.sysctl = {
      "kernel.sched_autogroup_enabled" = 1;
      "vm.zone_reclaim_mode" = 0;
      "vm.stat_interval" = 10;
    };

    systemd.settings.Manager = {
      DefaultTimeoutStartSec = "15s";
      DefaultTimeoutStopSec = "10s";
      DefaultDeviceTimeoutSec = "10s";
    };

    services.journald.extraConfig = ''
      SystemMaxUse=200M
    '';

    systemd.timers.logrotate.timerConfig.OnCalendar = lib.mkForce "daily";
  };

  performance = {
    # nixlytile and gametune own it later.
    powerManagement.cpuFreqGovernor = "performance";

    services.ananicy = {
      enable = true;
      package = pkgs.ananicy-cpp;
      rulesProvider = pkgs.ananicy-rules-cachyos;
      # Root cgroup hid nixlytile from polkit.
      settings.cgroup_realtime_workaround = lib.mkForce false;
      # Match nixlytile's nice -10.
      extraTypes = [
        { type = "Game"; nice = -10; ioclass = "best-effort"; ionice = 0; }
      ];
      # Sessions inherited SCHED_IDLE from sddm.
      extraRules = [
        { name = "sddm"; nice = 0; sched = "other"; ioclass = "best-effort"; }
        { name = "sddm-helper"; nice = 0; sched = "other"; ioclass = "best-effort"; }
        # War Thunder rule idled thelastemperor.
        { name = "launcher"; type = "Game"; }
      ];
    };

    # Idle slice outside system.slice.
    systemd.slices.background.sliceConfig = {
      CPUWeight = "idle";
      IOWeight = 10;
    };

    # MGLRU keeps the working set.
    systemd.tmpfiles.rules = [
      "w /sys/kernel/mm/lru_gen/min_ttl_ms - - - - 1000"
    ];

    services.udev.extraRules = ''
      ACTION=="add|change", KERNEL=="nvme[0-9]*n[0-9]*", ATTR{queue/scheduler}="none"
      ACTION=="add|change", KERNEL=="sd[a-z]*", ATTR{queue/scheduler}="bfq"

      # Compositor owns governor and EPP.
      ACTION=="add|change", SUBSYSTEM=="cpu", RUN+="${pkgs.bash}/bin/sh -c 'chgrp users /sys/devices/system/cpu/cpufreq/policy*/scaling_governor /sys/devices/system/cpu/cpufreq/policy*/energy_performance_preference 2>/dev/null; chmod 0664 /sys/devices/system/cpu/cpufreq/policy*/scaling_governor /sys/devices/system/cpu/cpufreq/policy*/energy_performance_preference 2>/dev/null || true'"

      # nixlytile raises the iGPU floor.
      ACTION=="add|change", SUBSYSTEM=="drm", ENV{DEVTYPE}=="drm_minor", DRIVERS=="i915|xe", RUN+="${pkgs.bash}/bin/sh -c 'cd /sys%p && chgrp users gt_min_freq_mhz device/tile0/gt0/freq0/min_freq 2>/dev/null; chmod 0664 gt_min_freq_mhz device/tile0/gt0/freq0/min_freq 2>/dev/null || true'"

    '' + lib.optionalString laptop ''
      # Laptop runtime PM, Bluetooth exempt.
      ACTION=="add", SUBSYSTEM=="pci", TEST=="power/control", ATTR{power/control}="auto"
      ACTION=="add", SUBSYSTEM=="usb", ATTR{bDeviceClass}!="e0", TEST=="power/control", ATTR{power/control}="auto"
      # Keyboards keep their backlight.
      ACTION=="add", SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_interface", ATTR{bInterfaceClass}=="03", RUN+="${pkgs.bash}/bin/sh -c 'echo on > /sys$env{DEVPATH}/../power/control'"
    '';

    # Audio and games get rtprio.
    security.pam.loginLimits = [
      { domain = "*"; type = "soft"; item = "nofile"; value = "524288"; }
      { domain = "*"; type = "hard"; item = "nofile"; value = "1048576"; }
      { domain = "*"; type = "soft"; item = "memlock"; value = "unlimited"; }
      { domain = "*"; type = "hard"; item = "memlock"; value = "unlimited"; }
      { domain = "@audio"; type = "soft"; item = "rtprio"; value = "95"; }
      { domain = "@audio"; type = "hard"; item = "rtprio"; value = "95"; }
      { domain = "@gamemode"; type = "soft"; item = "rtprio"; value = "95"; }
      { domain = "@gamemode"; type = "hard"; item = "rtprio"; value = "95"; }
      { domain = "@gamemode"; type = "soft"; item = "nice"; value = "-20"; }
      { domain = "@gamemode"; type = "hard"; item = "nice"; value = "-20"; }
    ];

    boot.kernel.sysctl = {
      "fs.inotify.max_user_watches" = 524288;
      "fs.inotify.max_user_instances" = 8192;
      "fs.file-max" = 2097152;
      "fs.aio-max-nr" = 1048576;
      "kernel.split_lock_mitigate" = 0;
      # Game mode compacts explicitly.
      "vm.compaction_proactiveness" = 0;
      "vm.watermark_boost_factor" = 0;
      # CachyOS value against stalls.
      "vm.page_lock_unfairness" = 1;
    };
  };

  memory = {
    zramSwap = {
      enable = true;
      memoryPercent = 100;
      # lz4 for weak CPUs.
      algorithm = if hw.cpuLevel >= 3 && hw.cores >= 8 then "zstd" else "lz4";
      priority = 100;
    };

    # Avoids compressing twice.
    boot.kernelParams = [ "zswap.enabled=0" ];

    boot.kernel.sysctl = {
      "vm.swappiness" = 180;
      "vm.page-cluster" = 0;
      "vm.vfs_cache_pressure" = 50;
      # Bytes, stable under pressure.
      "vm.dirty_background_bytes" = 67108864;
      "vm.dirty_bytes" = 268435456;
      "vm.dirty_expire_centisecs" = 3000;
      "vm.dirty_writeback_centisecs" = 1500;
      # Games over-allocate.
      "vm.overcommit_memory" = 1;
    };

    # earlyoom is the only killer.
    systemd.oomd.enable = false;
  };

  power = {
    # logind owns lid and keys.
    services.acpid.enable = lib.mkForce false;

    # nixlytile writes these knobs.
    systemd.services.platform-profile-perms = {
      description = "Make power/clock/backlight sysfs files writable for the users group";
      wantedBy = [ "multi-user.target" ];
      after = [ "systemd-modules-load.service" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "platform-profile-perms" ''
          for f in /sys/firmware/acpi/platform_profile \
                   /sys/devices/platform/msi-ec/shift_mode \
                   /sys/devices/system/cpu/intel_pstate/no_turbo \
                   /sys/devices/system/cpu/cpufreq/boost \
                   /sys/devices/system/cpu/cpufreq/policy*/scaling_max_freq \
                   /sys/devices/system/cpu/cpufreq/policy*/scaling_min_freq \
                   /sys/class/power_supply/BAT*/charge_control_start_threshold \
                   /sys/class/power_supply/BAT*/charge_control_end_threshold \
                   /sys/class/backlight/*/brightness; do
            if [ -e "$f" ]; then
              ${pkgs.coreutils}/bin/chgrp users "$f"
              ${pkgs.coreutils}/bin/chmod 0664 "$f"
            fi
          done
        '';
      };
    };

    # Reboot without a password.
    security.polkit.extraConfig = ''
      polkit.addRule(function(action, subject) {
        if ((action.id == "org.freedesktop.login1.reboot" ||
             action.id == "org.freedesktop.login1.reboot-multiple-sessions" ||
             action.id == "org.freedesktop.login1.power-off" ||
             action.id == "org.freedesktop.login1.power-off-multiple-sessions") &&
            subject.user == "${nixlyUser}") {
          return polkit.Result.YES;
        }
      });
    '';

    # nixly-idled locks the screen.
    services.logind.settings.Login = {
      IdleAction = "ignore";
      IdleActionSec = 0;
      HandleLidSwitch = lib.mkDefault "suspend";
      HandleLidSwitchExternalPower = lib.mkDefault "suspend";
      HandleLidSwitchDocked = "ignore";
    };
  };

  # Resume reads an EFI variable.
  hibernate =
    let
      nvidia = builtins.elem "nvidia" config.services.xserver.videoDrivers;
      # amdgpu evicts VRAM to RAM.
      vramGiB = if laptop && (hwData.detected.amdDgpu or (hwData.detected.amd != "")) then 16 else 0;
    in
    lib.mkIf (bootMode == "efi") {
      swapDevices = [{
        device = "/swapfile";
        size = (hw.memGiB + vramGiB + 5) * 1024;
        priority = 0;
      }];

      systemd.tmpfiles.rules = [
        "w /sys/power/image_size - - - - ${toString (hw.memGiB * 1024 * 1024 * 1024)}"
      ];

      # Suspend-then-hibernate hung resuming.
      services.logind.settings.Login = lib.mkIf laptop {
        HandleLidSwitch = "hibernate";
        HandleLidSwitchExternalPower = "hibernate";
      };

      # Keeps VRAM off tmpfs.
      hardware.nvidia = lib.mkIf
        (laptop && nvidia
          && lib.versionAtLeast config.hardware.nvidia.package.version "430.09")
        {
          powerManagement.enable = lib.mkForce true;
          moduleParams.nvidia.NVreg_TemporaryFilePath = "/var/tmp";
        };
    };

  tools = {
    environment.systemPackages = with pkgs; [
      nixlyos-detect-hw
      nixlyos-user-config
      nixlyos-update
      nixlyos-stage
    ];

    # Stages the next generation.
    systemd.services.nixlyos-stage = {
      description = "Stage the next NixlyOS generation in the background";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        User = nixlyUser;
        ExecStart = "${pkgs.nixlyos-stage}/bin/nixlyos-stage";
        Nice = 19;
        CPUSchedulingPolicy = "idle";
        IOSchedulingClass = "idle";
      };
    };

    systemd.timers.nixlyos-stage = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "2min";
        OnUnitActiveSec = "5min";
        RandomizedDelaySec = "1min";
        Persistent = true;
      };
    };
  };
in
{
  imports = [
    mode
    identity
    boot
    initrd
    nix
    users
    locale
    services
    performance
    memory
    power
    hibernate
    tools
  ];
}
