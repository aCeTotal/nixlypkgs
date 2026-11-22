-- +goose Up
ALTER TABLE modules
    ADD COLUMN required boolean NOT NULL DEFAULT false,
    ADD COLUMN position integer;

-- +goose StatementBegin
INSERT INTO modules (slug, title, description, required, position, source) VALUES
('system', 'System', 'Oppstart, kjerne, Nix, brukere, språk, ytelse, minne, strøm og oppdateringsverktøy.', true, 1, $nix${ config, lib, pkgs, inputs, hwData, nixlyUser, ... }:

let
  isHtpc = config.nixlyos.mode == "htpc";
  isArm = hwData.platform.arch == "aarch64";
  bootMode = hwData.platform.bootMode or "efi";
  # Battery policy, never the HTPC.
  laptop = hwData.dmi.isLaptop && !isHtpc;
  hw = hwData.resources;

  mode = {
    options.nixlyos.mode = lib.mkOption {
      type = lib.types.enum [ "desktop" "htpc" ];
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

      # Overlay attrs keep cache hits.
      kernelPackages =
        if isArm
        then pkgs.linuxPackages_latest
        else if hw.cpuLevel >= 3
        then pkgs.linuxPackages_nixlyos_v3
        else pkgs.linuxPackages_nixlyos;

      kernelParams = [
        "quiet"
        "loglevel=3"
        "rd.udev.log_level=3"
        "udev.log_priority=3"
        "systemd.show_status=false"
        "rd.systemd.show_status=false"
      ]
      ++ lib.optional (!isArm) "8250.nr_uarts=0"
      ++ [
        "transparent_hugepage=madvise"
      ]
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
      after = [ "msi-ec-autoload.service" ];
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
$nix$),
('security', 'Sikkerhet', 'Brannmur, sandkasse, redusert angrepsflate, Secure Boot og øyeblikksbilder.', true, 2, $nix${ config, lib, pkgs, inputs, hwData, ... }:

let
  firewall = {
    networking.firewall.enable = true;
    # One transaction at boot.
    networking.nftables.enable = true;
    # No free LAN discovery.
    networking.firewall.allowPing = false;

    # Crashes never spill memory.
    systemd.coredump.enable = false;

    security.apparmor.enable = false;
  };

  # Steam stays unjailed for Proton.
  sandbox =
    let
      # Blocks the systemd1 escape.
      dbusFilter = [
        "--dbus-user=filter"
        "--dbus-user.talk=org.freedesktop.Notifications"
        "--dbus-user.talk=org.freedesktop.secrets"
        "--dbus-user.talk='org.freedesktop.portal.*'"
        "--dbus-user.talk=org.freedesktop.ScreenSaver"
        "--dbus-user.talk=ca.desrt.dconf"
        "--dbus-user.own='org.mpris.MediaPlayer2.*'"
      ];
      dbusArgs = builtins.concatStringsSep " \\\n          " dbusFilter;

      jail = final: { pkg, bin, profile, extraArgs ? [ ] }:
        final.symlinkJoin {
          name = "${bin}-jailed";
          paths = [ pkg ];
          inherit (pkg) meta;
          postBuild = ''
            rm -f $out/bin/${bin}
            cat > $out/bin/${bin} <<'EOF'
            #!${final.runtimeShell} -e
            # Options first: joining rejects them after.
            exec /run/wrappers/bin/firejail --quiet \
              ${builtins.concatStringsSep " " extraArgs} \
              --profile=${final.firejail}/etc/firejail/${profile}.profile \
              ${dbusArgs} \
              --join-or-start=${bin} ${pkg}/bin/${bin} "$@"
            EOF
            chmod 0755 $out/bin/${bin}

            # Launchers hardcode the unwrapped store path.
            for d in $out/share/applications/*.desktop; do
              [ -e "$d" ] || continue
              real=$(readlink -f "$d")
              rm "$d"
              substitute "$real" "$d" --replace-quiet "${pkg}/bin/${bin}" "$out/bin/${bin}"
            done
          '';
        };
    in
    {
      programs.firejail.enable = true;

      # firejail spawns it from PATH.
      environment.systemPackages = [ pkgs.xdg-dbus-proxy ];

      nixpkgs.overlays = [
        (final: prev: {
          brave = jail final {
            pkg = prev.brave;
            bin = "brave";
            profile = "brave-browser";
            extraArgs = [
              "'--ignore=whitelist \${HOME}/.gnupg'"
              "--private-tmp"
              # GTK theme reads wallpaper colours.
              "'--whitelist=\${HOME}/.local/state/nixly-theme'"
              "'--read-only=\${HOME}/.local/state/nixly-theme'"
            ];
          };
        })
      ];

      # Portal file picks into firejail.
      systemd.services.nixly-jaild = {
        description = "nixlytile sandbox file grant helper";
        wantedBy = [ "multi-user.target" ];
        path = [ pkgs.polkit ];
        serviceConfig = {
          Type = "exec";
          ExecStart = "${pkgs.nixlytile}/bin/nixly-jaild";
          Restart = "on-failure";
          RestartSec = 5;
          NoNewPrivileges = true;
          ProtectSystem = "strict";
          ReadWritePaths = [ "/run" ];
          ProtectHome = "read-only";
          ProtectHostname = true;
          ProtectKernelTunables = true;
          ProtectKernelModules = true;
          ProtectKernelLogs = true;
          ProtectControlGroups = true;
          PrivateNetwork = true;
          RestrictAddressFamilies = [ "AF_UNIX" ];
          RestrictNamespaces = [ "mnt" ];
          RestrictRealtime = true;
          LockPersonality = true;
          MemoryDenyWriteExecute = true;
          SystemCallArchitectures = "native";
          SystemCallFilter = [ "@system-service" "@mount" "setns" ];
          CapabilityBoundingSet = [
            "CAP_SYS_ADMIN"
            "CAP_SYS_CHROOT"
            "CAP_SYS_PTRACE"
            "CAP_DAC_OVERRIDE"
            "CAP_DAC_READ_SEARCH"
            "CAP_CHOWN"
            "CAP_SETUID"
            "CAP_SETGID"
          ];
        };
      };

      # File picks never prompt.
      security.polkit.extraConfig = ''
        polkit.addRule(function(action, subject) {
          if (action.id == "org.nixlytile.jail-grant" && subject.local && subject.active) {
            return polkit.Result.YES;
          }
        });
      '';
    };

  surface =
    let
      # Last peer gone: boltd exits.
      boltIdle = pkgs.writeShellScript "bolt-idle" ''
        for d in /sys/bus/thunderbolt/devices/*-*; do
          case ''${d##*/} in *-0|*:*) continue ;; esac
          [ -e "$d" ] && exit 0
        done
        exec ${pkgs.systemd}/bin/systemctl stop --no-block bolt.service
      '';
    in
    {
      # Unused code hostile devices reach.
      boot.blacklistedKernelModules = [
        "firewire-core"
        "firewire-ohci"
        "firewire-sbp2"

        "dccp"
        "sctp"
        "rds"
        "tipc"
        "n-hdlc"
        "ax25"
        "netrom"
        "x25"
        "rose"
        "decnet"
        "econet"
        "af_802154"
        "ipx"
        "appletalk"
        "psnap"
        "p8023"
        "p8022"
        "atm"

        "cramfs"
        "freevxfs"
        "jffs2"
        "hfs"
        "hfsplus"
        "gfs2"
        "ksmbd"

        "vivid"
      ] ++ lib.optionals (hwData.platform.arch != "aarch64") [
        "parport_pc"
        "ppdev"
      ];

      # BIOS must require user authorization.
      services.hardware.bolt.enable = true;

      # Only a plugged peer wakes boltd.
      services.udev.extraRules = ''
        SUBSYSTEM=="thunderbolt", ENV{DEVTYPE}!="thunderbolt_device", ENV{SYSTEMD_WANTS}=""
        SUBSYSTEM=="thunderbolt", KERNEL=="*-0", ENV{SYSTEMD_WANTS}=""
        ACTION=="remove", SUBSYSTEM=="thunderbolt", ENV{DEVTYPE}=="thunderbolt_device", RUN+="${boltIdle}"
      '';
    };

  secureboot =
    let
      cfg = config.nixlyos.secureBoot;

      helper = pkgs.writeShellApplication {
        name = "nixly-secureboot";
        runtimeInputs = with pkgs; [ sbctl systemd coreutils gnugrep ];
        text = ''
          status() {
            sbctl status || true
            echo
            bootctl status 2>/dev/null | grep -iE "secure boot|tpm2" || true
          }

          setup() {
            [ "$(id -u)" = 0 ] || { echo "run as root"; exit 1; }
            sbctl create-keys
            if bootctl status 2>/dev/null | grep -qi "setup mode: *setup"; then
              # Vendor certs keep option ROMs.
              sbctl enroll-keys --microsoft
              echo "keys enrolled — set nixlyos.secureBoot.enable = true, rebuild, reboot"
            else
              echo "firmware is not in setup mode: clear the platform keys in the"
              echo "UEFI menu (Security > Secure Boot > Key Management > delete all"
              echo "keys), boot back here and run 'nixly-secureboot setup' again."
            fi
          }

          case "''${1:-status}" in
            status) status ;;
            setup)  setup ;;
            verify) sbctl verify ;;
            *) echo "usage: nixly-secureboot [status|setup|verify]"; exit 1 ;;
          esac
        '';
      };
    in
    {
      imports = [ inputs.lanzaboote.nixosModules.lanzaboote ];

      options.nixlyos.secureBoot = {
        enable = lib.mkEnableOption "signed boot chain (lanzaboote + sbctl keys)";

        pkiBundle = lib.mkOption {
          type = lib.types.str;
          default = "/var/lib/sbctl";
          description = "Directory holding the Secure Boot signing keys.";
        };
      };

      config = lib.mkMerge [
        {
          environment.systemPackages = [ pkgs.sbctl helper ];

          # PCRs for later TPM unlock.
          security.tpm2 = {
            enable = true;
            pkcs11.enable = true;
            tctiEnvironment.enable = true;
          };
        }

        (lib.mkIf cfg.enable {
          # Signs every generation at build.
          boot.loader.systemd-boot.enable = lib.mkForce false;
          boot.lanzaboote = {
            enable = true;
            pkiBundle = cfg.pkiBundle;
            configurationLimit = config.boot.loader.systemd-boot.configurationLimit;
          };

          # Unsigned generations never install.
          system.activationScripts.nixlySecureBootKeys = ''
            if [ ! -s ${cfg.pkiBundle}/keys/db/db.key ]; then
              echo "secure boot: no signing keys in ${cfg.pkiBundle}." >&2
              echo "run 'nixly-secureboot setup' or unset nixlyos.secureBoot.enable" >&2
              exit 1
            fi
          '';
        })
      ];
    };

  # Malware cannot rewrite them.
  snapshots =
    let
      rootFs = config.fileSystems."/";
      keepHourly = 24;
      keepDaily = 14;

      snapshot = pkgs.writeShellApplication {
        name = "nixly-snapshot";
        runtimeInputs = with pkgs; [ btrfs-progs coreutils util-linux ];
        text = ''
          dev=${rootFs.device}
          top=/run/nixly-snapshots
          mkdir -p "$top"
          mount -o subvolid=5,noatime "$dev" "$top"
          trap 'umount "$top"' EXIT

          dest="$top/@snapshots"
          [ -d "$dest" ] || btrfs subvolume create "$dest"
          chmod 700 "$dest"

          stamp=$(date +%Y%m%d-%H%M%S)
          hour=$(date +%H)

          keep() {
            # shellcheck disable=SC2012
            ls -1d "$dest/$1-"* 2>/dev/null | sort | head -n "-$2" | while read -r old; do
              btrfs subvolume delete "$old" >/dev/null
            done
          }

          for sv in @root @home; do
            btrfs subvolume snapshot -r "$top/$sv" "$dest/$sv-hourly-$stamp" >/dev/null
            if [ "$hour" = "04" ]; then
              btrfs subvolume snapshot -r "$top/$sv" "$dest/$sv-daily-$stamp" >/dev/null
            fi
            keep "$sv-hourly" ${toString keepHourly}
            keep "$sv-daily" ${toString keepDaily}
          done
        '';
      };
    in
    lib.mkIf (rootFs.fsType == "btrfs") {
      environment.systemPackages = [ snapshot ];

      systemd.services.nixly-snapshot = {
        description = "Read-only btrfs snapshots of / and /home";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${snapshot}/bin/nixly-snapshot";
          PrivateMounts = true;
          PrivateNetwork = true;
          ProtectHostname = true;
          ProtectKernelModules = true;
          ProtectKernelLogs = true;
          RestrictAddressFamilies = [ "AF_UNIX" ];
          SystemCallArchitectures = "native";
          IOSchedulingClass = "idle";
          Nice = 19;
        };
      };

      systemd.timers.nixly-snapshot = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "hourly";
          Persistent = true;
          RandomizedDelaySec = "5m";
        };
      };
    };
in
{
  imports = [
    firewall
    sandbox
    surface
    secureboot
    snapshots
  ];
}
$nix$),
('network', 'Nettverk', 'TCP og DNS, WiFi, køstyring, VPN, SSH og NFS.', true, 3, $nix${ config, lib, pkgs, nixlyUser, ... }:

let
  # nixlyos kernel builds bbr3 in.
  hasBbr3 = lib.hasInfix "nixlyos" config.boot.kernelPackages.kernel.name;

  stack = {
    boot.kernelModules = lib.optional (!hasBbr3) "tcp_bbr" ++ [
      # iwlwifi may silently skip it.
      "iwlmvm"
    ];

    boot.kernel.sysctl = {
      "net.core.rmem_default" = 4194304;
      "net.core.wmem_default" = 4194304;
      "net.core.rmem_max" = 134217728;
      "net.core.wmem_max" = 134217728;
      "net.ipv4.tcp_rmem" = "4096 262144 134217728";
      "net.ipv4.tcp_wmem" = "4096 262144 134217728";
      "net.core.optmem_max" = 65536;

      # Least bufferbloat, highest throughput.
      "net.core.default_qdisc" = "cake";
      "net.ipv4.tcp_congestion_control" = if hasBbr3 then "bbr3" else "bbr";

      "net.ipv4.tcp_mtu_probing" = 1;
      "net.ipv4.tcp_fastopen" = 3;
      "net.ipv4.tcp_ecn" = 1;
      "net.ipv4.tcp_sack" = 1;
      "net.ipv4.tcp_dsack" = 1;
      "net.ipv4.tcp_window_scaling" = 1;
      "net.ipv4.tcp_timestamps" = 1;
      "net.ipv4.tcp_notsent_lowat" = 131072;
      "net.ipv4.tcp_slow_start_after_idle" = 0;

      # Dead peers found in 2 min.
      "net.ipv4.tcp_keepalive_time" = 60;
      "net.ipv4.tcp_keepalive_intvl" = 10;
      "net.ipv4.tcp_keepalive_probes" = 6;

      "net.ipv4.tcp_tw_reuse" = 1;
      "net.ipv4.tcp_fin_timeout" = 10;
      "net.ipv4.tcp_max_syn_backlog" = 8192;

      "net.core.somaxconn" = 4096;
      "net.core.netdev_max_backlog" = 250000;
      "net.core.netdev_budget" = 600;
      "net.core.netdev_budget_usecs" = 8000;

      "net.ipv4.ip_local_port_range" = "10240 65535";

      # QUIC and game traffic.
      "net.ipv4.udp_rmem_min" = 16384;
      "net.ipv4.udp_wmem_min" = 16384;

      "net.core.rps_sock_flow_entries" = 32768;
    };

    services.resolved = {
      enable = true;
      settings.Resolve = {
        # Validation blocked legitimate domains.
        DNSSEC = "false";
        # Strict breaks captive portals.
        DNSOverTLS = "opportunistic";
        FallbackDNS = [
          "1.1.1.1#cloudflare-dns.com"
          "1.0.0.1#cloudflare-dns.com"
          "9.9.9.9#dns.quad9.net"
        ];
        LLMNR = "false";
      };
    };

    # DHCP resolvers are ignored.
    networking.nameservers = [
      "9.9.9.9#dns.quad9.net"
      "149.112.112.112#dns.quad9.net"
    ];

    # nixlytile drives wpa_supplicant.
    networking.useDHCP = false;
    networking.useNetworkd = true;
    systemd.network.enable = true;
    systemd.network.networks."40-wired" = {
      matchConfig.Name = "en* eth*";
      networkConfig.DHCP = "yes";
      dhcpV4Config.RouteMetric = 100;
      linkConfig.RequiredForOnline = "no";
    };
    # Phone tethering, behind ethernet.
    systemd.network.networks."42-usb" = {
      matchConfig.Name = "usb*";
      networkConfig.DHCP = "yes";
      dhcpV4Config.RouteMetric = 200;
      linkConfig.RequiredForOnline = "no";
    };
    systemd.network.networks."45-wifi" = {
      matchConfig.Name = "wl*";
      networkConfig.DHCP = "yes";
      dhcpV4Config.RouteMetric = 600;
      linkConfig.RequiredForOnline = "no";
    };
    systemd.network.wait-online.enable = false;

    networking.wireless = {
      enable = true;
      userControlled = true;
      # Popup-saved networks land here.
      allowAuxiliaryImperativeNetworks = true;
      scanOnLowSignal = false;
      extraConfig = ''
        disable_scan_offload=1
      '';
    };

    # Stable IPv6 address.
    networking.tempAddresses = "disabled";

    # AX210 crashes on 6 GHz.
    boot.extraModprobeConfig = ''
      options iwlwifi bt_coex_active=N power_save=0 11n_disable=8 disable_11ax=1
      options iwlmvm power_scheme=1
    '';

    environment.systemPackages = with pkgs; [
      iproute2
      iptables
      nftables
    ];
  };

  # Cake both ways, rate from speedtest.
  shaping =
    let
      cfg = config.nixlyos.net;
      num = v: lib.optionalString (v != null) (toString v);

      shape = pkgs.writeShellScript "nixly-shape" ''
        set -u
        TC=${pkgs.iproute2}/bin/tc
        IP=${pkgs.iproute2}/bin/ip

        for path in /sys/class/net/*; do
          IF=$(${pkgs.coreutils}/bin/basename "$path")
          case "$IF" in en*|eth*|wl*|usb*) ;; *) continue ;; esac

          down="${num cfg.wanDownMbit}"
          up="${num cfg.wanUpMbit}"

          # Measured rate beats the guess.
          if [ -r "/var/lib/nixly-shape/$IF" ]; then
            DOWN=""; UP=""
            . "/var/lib/nixly-shape/$IF"
            [ -n "$DOWN" ] && down="$DOWN"
            [ -n "$UP" ] && up="$UP"
          fi
          [ -n "$down" ] && [ -n "$up" ] || continue

          $TC qdisc replace dev "$IF" root cake \
            bandwidth "$up"Mbit diffserv4 ack-filter nat || continue

          ifb="ifb-$IF"
          $IP link show "$ifb" >/dev/null 2>&1 || $IP link add "$ifb" type ifb || continue
          $IP link set "$ifb" up
          $TC qdisc del dev "$IF" handle ffff: ingress 2>/dev/null || true
          $TC qdisc add dev "$IF" handle ffff: ingress
          $TC filter add dev "$IF" parent ffff: protocol all prio 10 matchall \
            action mirred egress redirect dev "$ifb"
          $TC qdisc replace dev "$ifb" root cake \
            bandwidth "$down"Mbit besteffort nat ingress
        done
      '';

      # Link must be unshaped while measuring.
      measure = pkgs.writeShellScript "nixly-speedtest" ''
        set -u
        export PATH=${lib.makeBinPath (with pkgs; [
          coreutils
          gawk
          iproute2
          jq
          speedtest-go
          systemd
        ])}

        systemctl is-active -q gfn-focus.service && exit 0
        systemctl is-active -q nixly-gametune.service && exit 0

        route=$(ip -o route get 1.1.1.1 2>/dev/null) || exit 0
        IF=$(echo "$route" | awk '{for (i=1;i<NF;i++) if ($i=="dev") print $(i+1)}')
        SRC=$(echo "$route" | awk '{for (i=1;i<NF;i++) if ($i=="src") print $(i+1)}')
        [ -n "$IF" ] && [ -n "$SRC" ] || exit 0

        # Shaping returns on any exit.
        trap 'systemctl restart nixly-shape.service' EXIT

        tc qdisc del dev "$IF" root 2>/dev/null || true
        tc qdisc del dev "$IF" handle ffff: ingress 2>/dev/null || true

        json=$(speedtest-go --json --source "$SRC" 2>/dev/null) || exit 0
        dl=$(echo "$json" | jq -r '.servers[0].dl_speed // empty')
        ul=$(echo "$json" | jq -r '.servers[0].ul_speed // empty')
        [ -n "$dl" ] && [ -n "$ul" ] || exit 0

        # Bytes/s to Mbit, 94 %.
        down=$(echo "$dl" | awk '{printf "%d", $1 * 8 / 1000000 * 0.94}')
        up=$(echo "$ul" | awk '{printf "%d", $1 * 8 / 1000000 * 0.94}')

        # Keep the old file on nonsense.
        [ "$down" -ge 5 ] && [ "$up" -ge 5 ] || exit 0
        [ "$down" -le 10000 ] && [ "$up" -le 10000 ] || exit 0

        printf 'DOWN=%s\nUP=%s\n' "$down" "$up" > "/var/lib/nixly-shape/$IF"
      '';
    in
    {
      options.nixlyos.net = {
        wanDownMbit = lib.mkOption {
          type = lib.types.nullOr lib.types.ints.positive;
          default = null;
          example = 940;
          description = "Downlink fallback until speedtest.nix has measured this link.";
        };

        wanUpMbit = lib.mkOption {
          type = lib.types.nullOr lib.types.ints.positive;
          default = null;
          example = 940;
          description = "Uplink fallback until speedtest.nix has measured this link.";
        };

        autoMeasure = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Measure the WAN rate at boot instead of trusting wanDownMbit/wanUpMbit.";
        };
      };

      config = lib.mkMerge [
        {
          boot.kernelModules = [ "ifb" "sch_cake" "act_mirred" ];
          # The script names one per link.
          boot.extraModprobeConfig = "options ifb numifbs=0";

          systemd.services.nixly-shape = {
            description = "cake WAN shaping on every link";
            wantedBy = [ "multi-user.target" ];
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              ExecStart = "${shape}";
              StateDirectory = "nixly-shape";
            };
          };

          services.udev.extraRules = ''
            SUBSYSTEM=="net", ACTION=="add", RUN+="${pkgs.systemd}/bin/systemctl --no-block restart nixly-shape.service"
          '';
        }

        (lib.mkIf cfg.autoMeasure {
          systemd.services.nixly-speedtest = {
            description = "Measure WAN rate for cake shaping";
            # 300 MB of radio time.
            unitConfig.ConditionACPower = true;
            after = [ "network-online.target" ];
            wants = [ "network-online.target" ];
            serviceConfig = {
              Type = "oneshot";
              ExecStart = "${measure}";
              StateDirectory = "nixly-shape";
              TimeoutStartSec = "5min";
            };
          };

          systemd.timers.nixly-speedtest = {
            wantedBy = [ "timers.target" ];
            timerConfig = {
              # After boot owns the line.
              OnBootSec = "90s";
              Persistent = false;
            };
          };
        })
      ];
    };

  # EEE and coalescing cost latency.
  latency =
    let
      tune = pkgs.writeShellScript "nixly-niclat" ''
        set -u
        ETHTOOL=${pkgs.ethtool}/bin/ethtool

        ncpu=$(${pkgs.coreutils}/bin/nproc)
        [ "$ncpu" -gt 32 ] && ncpu=32
        mask=$(printf '%x' $(( (1 << ncpu) - 1 )))

        for path in /sys/class/net/*; do
          IF=$(${pkgs.coreutils}/bin/basename "$path")
          case "$IF" in en*|eth*|wl*) ;; *) continue ;; esac

          $ETHTOOL --set-eee "$IF" eee off 2>/dev/null || true
          $ETHTOOL -C "$IF" adaptive-rx off rx-usecs 0 2>/dev/null || true

          # Covers non-Intel WiFi too.
          ${pkgs.iw}/bin/iw dev "$IF" set power_save off 2>/dev/null || true

          queues=$(ls -d "$path"/queues/rx-* 2>/dev/null | wc -l)
          if [ "$queues" = 1 ]; then
            echo 32768 > "$path/queues/rx-0/rps_flow_cnt" 2>/dev/null || true
            echo "$mask" > "$path/queues/rx-0/rps_cpus" 2>/dev/null || true
          fi
        done
      '';
    in
    {
      systemd.services.nixly-niclat = {
        description = "Latency tuning per network link (EEE, coalescing, RFS)";
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${tune}";
        };
      };

      services.udev.extraRules = ''
        SUBSYSTEM=="net", ACTION=="add", RUN+="${pkgs.systemd}/bin/systemctl --no-block restart nixly-niclat.service"
      '';
    };

  vpn = {
    boot.kernelModules = [
      "af_key"
      "ah4"
      "ah6"
      "esp4"
      "esp6"
      "xfrm_user"
      "xfrm_algo"
      "l2tp_core"
      "l2tp_netlink"
      "l2tp_ppp"
      "nf_conntrack_pptp"
      "nf_nat_pptp"
      "tun"
      "wireguard"
    ];

    environment.systemPackages = with pkgs; [
      openvpn
      wireguard-tools
      openconnect
      vpnc
      sstp
      strongswan
      libreswan
      openfortivpn
      (writeShellScriptBin "tailscale-init" ''
        set -e
        sudo systemctl start tailscaled
        sudo tailscale up --ssh
        until [ "$(tailscale status --json 2>/dev/null | ${jq}/bin/jq -r .BackendState)" = "Running" ]; do
          sleep 1
        done
        ip=$(tailscale ip -4 2>/dev/null | head -1)
        echo ""
        echo "Tailscale aktiv ($ip). Venter paa at LAN-ssh stenges..."
        for _ in $(seq 30); do
          sudo ${nftables}/bin/nft list chain inet nixos-fw input-allow 2>/dev/null \
            | grep -q 'tcp dport 22 accept' || break
          sleep 1
        done
        echo "SSH stengt for LAN/internett — naas naa kun via tailnettet:"
        echo "  ssh total@$(hostname)   # fra enhver tailnet-enhet, uten noekkel/passord"
        echo "Aktive ssh-oekter overlever; nye maa gaa via tailscale."
      '')
    ];

    services.strongswan = {
      enable = true;
      secrets = [ "/etc/ipsec.secrets" ];
    };

    # Tailscale SSH needs no keys.
    services.tailscale = {
      enable = true;
      extraUpFlags = [ "--ssh" ];
    };

    # Login once with netbird up.
    services.netbird.enable = true;

    # Started by hand, never at boot.
    systemd.services.strongswan.wantedBy = lib.mkForce [ ];
    systemd.services.tailscaled.wantedBy = lib.mkForce [ ];
    systemd.services.netbird.wantedBy = lib.mkForce [ ];

    networking.firewall.trustedInterfaces = [ "tailscale0" "wt0" ];

    # Wheel toggles VPN units.
    security.polkit.extraConfig = ''
      polkit.addRule(function(action, subject) {
        if (!subject.isInGroup("wheel"))
          return polkit.Result.NOT_HANDLED;
        // Start and stop, per unit.
        if (action.id == "org.freedesktop.systemd1.manage-units") {
          var unit = action.lookup("unit");
          if (unit &&
              (unit.indexOf("wg-quick") == 0 ||
               unit.indexOf("openvpn-") == 0 ||
               unit.indexOf("openconnect-") == 0 ||
               unit.indexOf("openfortivpn-") == 0 ||
               unit.indexOf("strongswan") == 0 ||
               unit.indexOf("tailscaled") == 0)) {
            return polkit.Result.YES;
          }
        }
        // Unit files lack a name.
        if (action.id == "org.freedesktop.systemd1.manage-unit-files" ||
            action.id == "org.freedesktop.systemd1.reload-daemon") {
          return polkit.Result.YES;
        }
        return polkit.Result.NOT_HANDLED;
      });
    '';
  };

  ssh = {
    # Private ranges only.
    networking.firewall.extraInputRules = ''
      ip saddr { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16 } tcp dport 22 accept
    '';

    services.openssh = {
      enable = true;
      openFirewall = false;
      settings = {
        PermitRootLogin = "no";
        PasswordAuthentication = true;
        PermitEmptyPasswords = false;
        KbdInteractiveAuthentication = false;
        PubkeyAuthentication = true;
        AllowUsers = [ nixlyUser ];
        X11Forwarding = false;
        AllowTcpForwarding = "yes";
        # Remote hosts never use local keys.
        AllowAgentForwarding = "no";
        MaxSessions = 4;
        MaxStartups = "3:50:10";
        UseDns = false;
        ClientAliveInterval = 30;
        ClientAliveCountMax = 3;
        MaxAuthTries = 3;
        LoginGraceTime = "20s";
        Compression = "no";
        KexAlgorithms = [
          "sntrup761x25519-sha512@openssh.com"
          "curve25519-sha256"
          "curve25519-sha256@libssh.org"
        ];
        Ciphers = [
          "chacha20-poly1305@openssh.com"
          "aes256-gcm@openssh.com"
          "aes256-ctr"
        ];
        Macs = [
          "hmac-sha2-512-etm@openssh.com"
          "hmac-sha2-256-etm@openssh.com"
        ];
      };
    };

    programs.ssh = {
      startAgent = false;
      extraConfig = ''
        Host *
          ServerAliveInterval 20
          ServerAliveCountMax 3
          AddKeysToAgent yes
          ForwardAgent no
      '';
    };
  };

  nfs =
    let
      nfsOptions = lib.concatStringsSep "," [
        "rw"
        "vers=4.2"
        "rsize=1048576"
        "wsize=1048576"
        "nconnect=8"
        "soft"
        "timeo=5"
        "retrans=2"
        "retry=0"
        "fsc"
        "acl"
        "noatime"
        "nodiratime"
        "tcp"
        "lookupcache=all"
        "actimeo=300"
        "nocto"
      ];

      share = name: {
        what = "10.0.0.8:/${lib.toLower name}";
        where = "/mnt/nfs/${name}";
        type = "nfs";
        mountConfig = {
          Options = nfsOptions;
          TimeoutSec = "5s";
        };
        requires = [ "nfs-bigdisk1-check.service" ];
        after = [ "nfs-bigdisk1-check.service" "network-online.target" ];
        wants = [ "network-online.target" ];
        unitConfig = {
          StartLimitIntervalSec = 0;
        };
      };

      # Unmounting drops every cache.
      automount = name: {
        where = "/mnt/nfs/${name}";
        automountConfig = {
          TimeoutIdleSec = 0;
        };
        wantedBy = [ "multi-user.target" ];
      };

      shares = [ "Bigdisk1" "Bigdisk2" ];
    in
    {
      boot.supportedFilesystems = [ "nfs" ];

      # Only NFSv3 needs it.
      services.rpcbind.enable = lib.mkForce false;

      services.cachefilesd = {
        enable = true;
        extraConfig = ''
          brun 20%
          bcull 10%
          bstop 5%
          frun 20%
          fcull 10%
          fstop 5%
        '';
      };

      systemd.tmpfiles.rules = [
        "d /mnt/nfs 0755 root root -"
        "d /mnt/nfs/Bigdisk1 0755 root root -"
        "d /mnt/nfs/Bigdisk2 0755 root root -"
      ];

      # Fails in a second, never blocks.
      systemd.services.nfs-bigdisk1-check = {
        description = "Check NFS server 10.0.0.8 reachability";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${pkgs.bash}/bin/bash -c '${pkgs.iputils}/bin/ping -c 1 -W 1 10.0.0.8 > /dev/null 2>&1'";
        };
        unitConfig = {
          StartLimitIntervalSec = 0;
        };
      };

      systemd.mounts = map share shares;
      systemd.automounts = map automount shares;

      # statfs keeps connections warm.
      systemd.services.nfs-keepalive = {
        description = "Keep NFS mounts mounted and their connections warm";
        wantedBy = [ "multi-user.target" ];
        after = [ "remote-fs.target" ];
        serviceConfig = {
          ExecStart = pkgs.writeShellScript "nfs-keepalive" ''
            while :; do
              for d in /mnt/nfs/*; do
                ${pkgs.coreutils}/bin/stat -f "$d" > /dev/null 2>&1 &
              done
              wait
              ${pkgs.coreutils}/bin/sleep 30
            done
          '';
          Restart = "always";
        };
      };

      # One rsize measured fastest.
      systemd.services.nfs-readahead = {
        description = "Raise NFS readahead to one rsize (1 MB)";
        after = [ "mnt-nfs-Bigdisk1.mount" "mnt-nfs-Bigdisk2.mount" ];
        wantedBy = [ "mnt-nfs-Bigdisk1.mount" "mnt-nfs-Bigdisk2.mount" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = pkgs.writeShellScript "nfs-readahead" ''
            set -u
            # Third mountinfo field is maj:min.
            while read -r _ _ majmin _ _ _ rest; do
              case "$rest" in
                *" nfs "*|*" nfs4 "*) ;;
                *) continue ;;
              esac
              f=/sys/class/bdi/$majmin/read_ahead_kb
              [ -w "$f" ] && echo 1024 > "$f"
            done < /proc/self/mountinfo
            exit 0
          '';
        };
      };
    };
in
{
  imports = [
    stack
    shaping
    latency
    vpn
    ssh
    nfs
  ];
}
$nix$),
('session', 'Skrivebord', 'Wayland, nixlytile, innlogging, mus og tastatur.', true, 4, $nix${ config, lib, pkgs, hwData, ... }:

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
$nix$),
('audio', 'Lyd og Bluetooth', 'PipeWire, mikrofonkjede, push-to-talk og Bluetooth.', true, 5, $nix${ pkgs, ... }:

let
  sound = {
    security.rtkit.enable = true;
    services.pulseaudio.enable = false;

    services.pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
      jack.enable = true;
      wireplumber.enable = true;

      wireplumber.extraConfig = {
        # Codecs every HDMI TV knows.
        "51-hdmi-iec958-codecs" = {
          "monitor.alsa.rules" = [
            {
              matches = [
                { "alsa.card_name" = "~HDA Intel HDMI"; }
              ];
              actions = {
                update-props = {
                  "api.alsa.iec958.codecs" = [ "PCM" "AC3" "EAC3" ];
                };
              };
            }
          ];
        };

        # Empty profiles crashed Steam's libaudio.
        "52-no-split-pcm" = {
          "monitor.alsa.rules" = [
            {
              matches = [
                { "device.name" = "~alsa_card.*"; }
              ];
              actions = {
                update-props = {
                  "api.alsa.split-enable" = false;
                };
              };
            }
          ];
        };

        # Falls back to "off" profile.
        "53-acp-auto-profile" = {
          "monitor.alsa.rules" = [
            {
              matches = [
                { "device.name" = "~alsa_card.*"; }
              ];
              actions = {
                update-props = {
                  "api.acp.auto-profile" = true;
                };
              };
            }
          ];
        };
      };

      extraConfig = {
        pipewire."92-low-latency" = {
          "context.properties" = {
            "default.clock.rate" = 48000;
            "default.clock.allowed-rates" = [ 48000 44100 96000 192000 ];
            # 2.7 ms for games.
            "default.clock.quantum" = 128;
            # 32 caused RT wakeup storms.
            "default.clock.min-quantum" = 64;
            "default.clock.max-quantum" = 2048;
            "log.level" = 2;
          };
          # Transparent at modest CPU.
          "stream.properties" = {
            "resample.quality" = 4;
          };
        };
        pipewire-pulse."92-low-latency" = {
          "stream.properties" = {
            "resample.quality" = 4;
          };
        };
      };
    };

    # Old WP 0.4 state wins otherwise.
    systemd.user.services.wireplumber-route-migrate = {
      description = "Rewrite stale WirePlumber 0.4 route state for WP 0.5";
      before = [ "wireplumber.service" ];
      partOf = [ "wireplumber.service" ];
      wantedBy = [ "wireplumber.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "wp-route-migrate" ''
          set -u
          STATE="''${XDG_STATE_HOME:-$HOME/.local/state}/wireplumber/default-routes"
          [ -f "$STATE" ] || exit 0
          ${pkgs.gnused}/bin/sed -i -E \
            's|"iec958Codecs":\[[^]]*\]|"iec958Codecs":["PCM", "AC3", "EAC3"]|g' \
            "$STATE"
        '';
      };
    };

    environment.systemPackages = with pkgs; [
      pipewire
      wireplumber
      bluez
      pavucontrol
      pwvucontrol
      crosspipe
      qpwgraph
      alsa-utils
    ];
  };

  # nixly-mic drives the gain stages.
  mic =
    let
      rnnoise = "${pkgs.rnnoise-plugin}/lib/ladspa/librnnoise_ladspa.so";
      swh = "${pkgs.ladspaPlugins}/lib/ladspa";
    in
    {
      services.pipewire.extraConfig.pipewire."99-nixly-mic" = {
        "context.modules" = [
          {
            # Meters before the gain stages.
            name = "libpipewire-module-filter-chain";
            args = {
              "node.description" = "NixlyMic tap";
              "media.name" = "NixlyMic tap";
              "filter.graph" = {
                nodes = [{ type = "builtin"; name = "thru"; label = "copy"; }];
                inputs = [ "thru:In" ];
                outputs = [ "thru:Out" ];
              };
              "node.link-group" = "nixly-mic-tap";
              "capture.props" = {
                "node.name" = "nixly-mic-tap-input";
                "node.description" = "NixlyMic tap input";
                "node.passive" = true;
                "audio.rate" = 48000;
                "audio.channels" = 1;
                "audio.position" = [ "MONO" ];
                "node.latency" = "480/48000";
              };
              "playback.props" = {
                "node.name" = "nixly-mic-tap";
                "node.description" = "NixlyMic tap";
                "media.class" = "Audio/Source";
                "audio.rate" = 48000;
                "audio.channels" = 1;
                "audio.position" = [ "MONO" ];
                "filter.smart" = true;
                "filter.smart.name" = "nixly-mic-tap";
                # Closest to the device.
                "filter.smart.after" = [ "nixly-mic" "nixly-ptt" ];
                "filter.smart.targetable" = true;
              };
            };
          }
          {
            name = "libpipewire-module-filter-chain";
            args = {
              "node.description" = "NixlyMic";
              "media.name" = "NixlyMic";
              "filter.graph" = {
                nodes = [
                  { type = "builtin"; name = "dc"; label = "dcblock"; }
                  {
                    type = "builtin";
                    name = "hpf";
                    label = "bq_highpass";
                    control = { "Freq" = 85.0; "Q" = 0.707; };
                  }
                  {
                    # Mains hum, voice untouched.
                    type = "builtin";
                    name = "hum1";
                    label = "bq_notch";
                    control = { "Freq" = 50.0; "Q" = 20.0; };
                  }
                  {
                    type = "builtin";
                    name = "hum2";
                    label = "bq_notch";
                    control = { "Freq" = 100.0; "Q" = 20.0; };
                  }
                  # ±40 dB digital range.
                  { type = "builtin"; name = "g1"; label = "linear"; control = { "Mult" = 1.0; }; }
                  { type = "builtin"; name = "g2"; label = "linear"; control = { "Mult" = 1.0; }; }
                  {
                    # Suppresses noise, never gates.
                    type = "ladspa";
                    name = "nr";
                    plugin = rnnoise;
                    label = "noise_suppressor_mono";
                    control = {
                      "VAD Threshold (%)" = 0.0;
                      "VAD Grace Period (ms)" = 200.0;
                      "Retroactive VAD Grace (ms)" = 60.0;
                    };
                  }
                  {
                    type = "ladspa";
                    name = "comp";
                    plugin = "${swh}/sc4m_1916.so";
                    label = "sc4m";
                    control = {
                      "RMS/peak" = 0.0;
                      "Attack time (ms)" = 8.0;
                      "Release time (ms)" = 180.0;
                      "Threshold level (dB)" = -26.0;
                      "Ratio (1:n)" = 3.0;
                      "Knee radius (dB)" = 3.0;
                      "Makeup gain (dB)" = 4.0;
                    };
                  }
                  {
                    type = "ladspa";
                    name = "lim";
                    plugin = "${swh}/fast_lookahead_limiter_1913.so";
                    label = "fastLookaheadLimiter";
                    control = {
                      "Input gain (dB)" = 0.0;
                      "Limit (dB)" = -1.5;
                      "Release time (s)" = 0.25;
                    };
                  }
                ];
                links = [
                  { output = "dc:Out 1"; input = "hpf:In"; }
                  { output = "hpf:Out"; input = "hum1:In"; }
                  { output = "hum1:Out"; input = "hum2:In"; }
                  { output = "hum2:Out"; input = "g1:In"; }
                  { output = "g1:Out"; input = "g2:In"; }
                  { output = "g2:Out"; input = "nr:Input"; }
                  { output = "nr:Output"; input = "comp:Input"; }
                  { output = "comp:Output"; input = "lim:Input 1"; }
                ];
                inputs = [ "dc:In 1" ];
                outputs = [ "lim:Output 1" ];
              };
              "node.link-group" = "nixly-mic";
              "capture.props" = {
                "node.name" = "nixly-mic-input";
                "node.description" = "NixlyMic input";
                "node.passive" = true;
                "audio.rate" = 48000;
                "audio.channels" = 1;
                "audio.position" = [ "MONO" ];
                # rnnoise needs 10 ms frames.
                "node.latency" = "480/48000";
              };
              "playback.props" = {
                "node.name" = "nixly-mic";
                "node.description" = "NixlyMic";
                "media.class" = "Audio/Source";
                "audio.rate" = 48000;
                "audio.channels" = 1;
                "audio.position" = [ "MONO" ];
                "filter.smart" = true;
                "filter.smart.name" = "nixly-mic";
                "filter.smart.before" = [ "nixly-mic-tap" ];
                "filter.smart.after" = [ "nixly-ptt" ];
                # Meeting apps skip push-to-talk.
                "filter.smart.targetable" = true;
              };
            };
          }
        ];
      };

      systemd.user.services.nixly-mic = {
        description = "Automatic microphone gain and noise control";
        after = [ "pipewire.service" "wireplumber.service" ];
        wants = [ "wireplumber.service" ];
        partOf = [ "pipewire.service" ];
        wantedBy = [ "pipewire.service" ];
        serviceConfig = {
          Type = "simple";
          ExecStart = "${pkgs.nixly-mic}/bin/nixly-mic";
          Restart = "always";
          RestartSec = 2;
          Slice = "session.slice";
        };
      };

      environment.systemPackages = [ pkgs.nixly-mic ];
    };

  # nixly-gate bit 0.
  pushToTalk = {
    services.pipewire.extraConfig.pipewire."99-nixly-ptt" = {
      "context.modules" = [
        {
          name = "libpipewire-module-filter-chain";
          args = {
            "node.description" = "NixlyMic push-to-talk";
            "media.name" = "NixlyMic push-to-talk";
            "filter.graph" = {
              nodes = [
                {
                  # Faded against release clicks.
                  type = "ladspa";
                  name = "gate";
                  plugin = "${pkgs.nixly-gate}/lib/ladspa/nixly_gate.so";
                  label = "nixly_gate";
                  control = { "Bit" = 0; "Fade (ms)" = 5.0; };
                }
              ];
            };
            "node.link-group" = "nixly-ptt";
            "capture.props" = {
              "node.name" = "nixly-ptt-input";
              "node.description" = "NixlyMic push-to-talk input";
              "node.passive" = true;
              "audio.rate" = 48000;
              "audio.channels" = 1;
              "audio.position" = [ "MONO" ];
              "node.latency" = "480/48000";
            };
            "playback.props" = {
              "node.name" = "nixly-ptt";
              "node.description" = "NixlyMic push-to-talk";
              "media.class" = "Audio/Source";
              "audio.rate" = 48000;
              "audio.channels" = 1;
              "audio.position" = [ "MONO" ];
              "filter.smart" = true;
              "filter.smart.name" = "nixly-ptt";
              # Closest to the app.
              "filter.smart.before" = [ "nixly-mic" ];
            };
          };
        }
      ];
    };
  };

  # Discord push-to-mute, nixly-gate bit 1.
  pushToMute =
    let
      source = "nixly-voip";
    in
    {
      services.pipewire.extraConfig.pipewire."99-nixly-voip" = {
        "context.modules" = [
          {
            name = "libpipewire-module-filter-chain";
            args = {
              "node.description" = "NixlyMic (Discord)";
              "media.name" = "NixlyMic (Discord)";
              "filter.graph" = {
                nodes = [
                  {
                    # Outlasts fade plus one quantum.
                    type = "ladspa";
                    name = "gate";
                    plugin = "${pkgs.nixly-gate}/lib/ladspa/nixly_gate.so";
                    label = "nixly_gate";
                    control = { "Bit" = 1; "Reopen (ms)" = 30.0; };
                  }
                ];
              };
              "node.link-group" = source;
              "capture.props" = {
                "node.name" = "${source}-input";
                "node.description" = "NixlyMic (Discord) input";
                "node.passive" = true;
                "audio.rate" = 48000;
                "audio.channels" = 1;
                "audio.position" = [ "MONO" ];
                "node.latency" = "480/48000";
              };
              "playback.props" = {
                "node.name" = source;
                "node.description" = "NixlyMic (Discord)";
                "media.class" = "Audio/Source";
                "audio.rate" = 48000;
                "audio.channels" = 1;
                "audio.position" = [ "MONO" ];
              };
            };
          }
        ];
      };

      services.pipewire.wireplumber.extraScripts."linking/find-voip-target.lua" = ''
        lutils = require ("linking-utils")
        cutils = require ("common-utils")

        -- Strict routes never use defaults.
        local ROUTES = {
          { target = "${source}", strict = true,
            clients = { "discord", "vesktop", "webcord" } },
          { target = "nixly-mic", strict = false,
            clients = { "teams", "wfica" } },
        }

        local function findRoute (props)
          if props ["media.class"] ~= "Stream/Input/Audio" or
              cutils.parseBool (props ["stream.capture.sink"]) then
            return nil
          end
          local name = string.lower ((props ["application.process.binary"] or "") ..
              " " .. (props ["application.name"] or ""))
          for _, route in ipairs (ROUTES) do
            for _, client in ipairs (route.clients) do
              if string.find (name, client, 1, true) then
                return route
              end
            end
          end
          return nil
        end

        -- Runs first, so moves cannot escape.
        SimpleEventHook {
          name = "linking/find-voip-target",
          before = "linking/find-defined-target",
          interests = {
            EventInterest {
              Constraint { "event.type", "=", "select-target" },
            },
          },
          execute = function (event)
            local _, om, _, props, flags, target =
                lutils:unwrap_select_target_event (event)

            if target then
              return
            end
            local route = findRoute (props)
            if not route then
              return
            end
            local node = om:lookup {
              type = "SiLinkable",
              Constraint { "node.name", "=", route.target },
            }
            if not node and route.strict then
              event:stop_processing ()
            end
            if not node then
              return
            end
            flags.has_defined_target = true
            flags.has_node_defined_target = false
            flags.can_passthrough = false
            event:set_data ("target", node)
          end
        }:register ()
      '';

      services.pipewire.wireplumber.extraConfig."99-nixly-voip" = {
        "wireplumber.components" = [
          {
            name = "linking/find-voip-target.lua";
            type = "script/lua";
            provides = "custom.find-voip-target";
          }
        ];
        "wireplumber.profiles" = {
          main = {
            "custom.find-voip-target" = "required";
          };
        };
      };
    };

  bluetooth =
    let
      pair = pkgs.writeShellApplication {
        name = "nixly-btpair";
        runtimeInputs = with pkgs; [
          bluez
          coreutils
          gnugrep
        ];
        text = ''
          # One-shot bluetoothctl lacks an agent.
          mac=''${1:-}
          if [[ -z $mac ]]; then
            echo "usage: nixly-btpair <mac>" >&2
            exit 1
          fi

          window=''${NIXLY_BTPAIR_WINDOW:-180}

          {
            echo "agent NoInputNoOutput"
            sleep 1
            echo "scan on"

            waited=0
            while (( waited < window )); do
              sleep 3
              waited=$(( waited + 3 ))
              if bluetoothctl info "$mac" | grep -q "Alias:"; then
                break
              fi
            done

            echo "pair $mac"
            sleep 12
            echo "trust $mac"
            sleep 1
            echo "connect $mac"
            sleep 8
            echo "quit"
          } | bluetoothctl >/dev/null 2>&1

          bluetoothctl info "$mac" | grep -q "Connected: yes"
        '';
      };

      watch = pkgs.writeShellApplication {
        name = "nixly-btwatch";
        runtimeInputs = [ pair ]
          ++ (with pkgs; [
          bluez
          coreutils
          gnused
        ]);
        text = ''
          events=/run/nixly-bt/events
          mkdir -p /run/nixly-bt
          chmod 755 /run/nixly-bt
          : >"$events"
          chmod 644 "$events"

          declare -A fails
          hit=0

          stdbuf -oL btmon --no-pager 2>/dev/null | while read -r line; do
            if [[ $line == *"PIN or Key Missing"* ]]; then
              hit=1
              continue
            fi

            if [[ $hit != 1 || $line != *"Address: "* ]]; then
              continue
            fi
            hit=0

            mac=''${line#*Address: }
            mac=''${mac%% *}

            # Dead keys fail every time.
            count=$(( ''${fails[$mac]:-0} + 1 ))
            fails[$mac]=$count
            if (( count < 3 )); then
              continue
            fi
            fails[$mac]=0

            name=$(bluetoothctl info "$mac" | sed -n 's/^[[:space:]]*Name: //p' | head -1)
            bluetoothctl remove "$mac" >/dev/null 2>&1 || true
            printf '%s|%s\n' "$mac" "''${name:-$mac}" >>"$events"
            nixly-btpair "$mac" >/dev/null 2>&1 &
          done
        '';
      };

      notify = pkgs.writeShellApplication {
        name = "nixly-btnotify";
        runtimeInputs = with pkgs; [
          coreutils
          libnotify
        ];
        text = ''
          events=/run/nixly-bt/events

          tail -F -n0 "$events" 2>/dev/null | while IFS='|' read -r _ name; do
            notify-send -u critical -a NixlyOS -t 0 "Controller lost its pairing" \
              "$name
          Hold the sync button until the logo flashes — it re-pairs on its own."
          done
        '';
      };
    in
    {
      hardware.bluetooth = {
        enable = true;
        powerOnBoot = true;
        package = pkgs.bluez-nixly;
        settings = {
          General = {
            Experimental = true;
            KernelExperimental = true;
            ControllerMode = "dual";
            FastConnectable = true;
            # Pads re-bond without removal.
            JustWorksRepairing = "always";
            # Fixed identity address.
            Privacy = "off";
            Class = "0x000100";
          };
          Policy = {
            AutoEnable = true;
            # Link loss only: bursts, then 30 s.
            ReconnectAttempts = 7200;
            ReconnectIntervals = "1,2,4,8,16,30";
            # Pads, audio sinks and handsfree.
            ReconnectUUIDs = "00001124-0000-1000-8000-00805f9b34fb,00001200-0000-1000-8000-00805f9b34fb,0000110b-0000-1000-8000-00805f9b34fb,0000111e-0000-1000-8000-00805f9b34fb";
          };
          LE = {
            MinAdvertisementInterval = 32;
            MaxAdvertisementInterval = 50;
            ScanIntervalAutoConnect = 60;
            # Higher duty jammed 2.4 GHz.
            ScanWindowAutoConnect = 15;
          };
          GATT = {
            Cache = "yes";
            Channels = 3;
            KeySize = 7;
          };
        };
      };

      # Autosuspend dropped headsets mid-use.
      boot.extraModprobeConfig = ''
        options btusb enable_autosuspend=0
      '';

      services.pipewire.wireplumber.extraConfig = {
        # The worn headset wins.
        "55-bluez-priority" = {
          "monitor.bluez.rules" = [
            {
              matches = [{ "node.name" = "~bluez_output\\..*"; }];
              actions = {
                update-props = {
                  "priority.session" = 4000;
                  "priority.driver" = 4000;
                };
              };
            }
          ];

          # Players follow profile switches.
          "wireplumber.settings" = {
            "linking.pause-playback" = false;
            "linking.follow-default-target" = true;
            "linking.allow-moving-streams" = true;
            # nixlytile flips it for LE Audio.
            "bluetooth.autoswitch-to-headset-profile" = false;
          };
        };

        # Silence keeps headsets awake.
        "54-bluez-keepalive" = {
          "monitor.bluez.rules" = [
            {
              matches = [
                { "node.name" = "~bluez_output\\..*"; }
              ];
              actions = {
                update-props = {
                  "session.suspend-timeout-seconds" = 0;
                  "node.pause-on-idle" = false;
                };
              };
            }
          ];
        };
      };

      environment.systemPackages = [ pair ];

      # bluez disables auto-connect after failures.
      systemd.services.nixly-btwatch = {
        description = "Purge Bluetooth bonds the peer no longer holds";
        after = [ "bluetooth.service" ];
        partOf = [ "bluetooth.service" ];
        wantedBy = [ "bluetooth.service" ];

        serviceConfig = {
          Type = "simple";
          ExecStart = "${watch}/bin/nixly-btwatch";
          Restart = "always";
          RestartSec = 5;
        };
      };

      # Re-pairing needs the sync button.
      systemd.user.services.nixly-btnotify = {
        description = "Bluetooth re-pairing notifications";
        partOf = [ "graphical-session.target" ];
        after = [ "graphical-session.target" ];
        wantedBy = [ "graphical-session.target" ];

        serviceConfig = {
          ExecStart = "${notify}/bin/nixly-btnotify";
          Restart = "on-failure";
          RestartSec = 3;
        };
      };
    };
in
{
  imports = [
    sound
    mic
    pushToTalk
    pushToMute
    bluetooth
  ];
}
$nix$),
('user', 'Brukermiljø', 'Skall, terminal, git, tema og editor.', true, 6, $nix${ nixlyUser, totalvimPkg, ... }:

let
  base = {
    home = {
      username = nixlyUser;
      homeDirectory = "/home/${nixlyUser}";
      stateVersion = "24.05";
      packages = [ totalvimPkg ];
      # PAM unlocks the login keyring.
      file.".local/share/keyrings/default".text = "login";
      sessionVariables = {
        EDITOR = "nvim";
        VISUAL = "nvim";
        BROWSER = "brave";
        TERMINAL = "alacritty";
      };
    };

    programs.bash.shellAliases = {
      "update" = "nixlyos-update";
      "nixly" = "cd $HOME/.local/nixlyos/";
    };

    dconf.settings = {
      "org/virt-manager/virt-manager/connections" = {
        autoconnect = [ "qemu:///system" ];
        uris = [ "qemu:///system" ];
      };
    };

    # Required by home-manager defaults.
    accounts.calendar.basePath = ".calendar";
    accounts.contact.basePath = ".contacts";

    programs.home-manager.enable = true;

    # Project compiler drives clangd.
    xdg.configFile."clangd/config.yaml".text = ''
      CompileFlags:
        Compiler: cc
    '';
  };

  bash =
    { pkgs, config, ... }:

    {
      home.packages = [ pkgs.eza ];

      programs = {
        bash = {
          enable = true;
          enableCompletion = true;

          shellAliases = {
            "z" = "zoxide";
            "pfo" = "cd /mnt/nfs/Bigdisk1/www/PFO";
            "work" = "cd /mnt/nfs/Bigdisk1/Work/painting";
            ".." = "cd ..";
            "ls" = "eza --long --all --header --group --git --icons --color=always";
          };

          # Commit everything and push.
          initExtra = ''
            push() {
                local msg
                if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
                    echo "push: not a git repo" >&2
                    return 1
                fi
                git add -A
                if git diff --cached --quiet; then
                    echo "push: nothing new to commit, pushing existing commits"
                    git push
                    return
                fi
                read -rep "commit> " msg || return 1
                if [ -z "$msg" ]; then
                    echo "push: empty message, aborted" >&2
                    git reset -q
                    return 1
                fi
                git commit -m "$msg" && git push
            }

            # Fast-forward a clean tree.
            pull() {
                if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
                    echo "pull: not a git repo" >&2
                    return 1
                fi
                if [ -n "$(git status --porcelain)" ]; then
                    echo "pull: uncommitted changes, aborted" >&2
                    return 1
                fi
                git fetch || return 1
                local behind
                behind=$(git rev-list --count HEAD..@{u} 2>/dev/null)
                if [ -z "$behind" ]; then
                    echo "pull: no upstream branch" >&2
                    return 1
                fi
                if [ "$behind" -eq 0 ]; then
                    echo "pull: already up to date"
                    return 0
                fi
                git pull --ff-only
            }

            # fetchFromGitHub fields for HEAD.
            hash() {
                local url owner_repo rev sha sri
                if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
                    echo "hash: not a git repo" >&2
                    return 1
                fi
                url=$(git remote get-url origin 2>/dev/null)
                if [ -z "$url" ]; then
                    echo "hash: no origin remote" >&2
                    return 1
                fi
                owner_repo=''${url#git@github.com:}
                owner_repo=''${owner_repo#https://github.com/}
                owner_repo=''${owner_repo%.git}
                rev=$(git rev-parse HEAD)
                if [ "$(git rev-parse @{u} 2>/dev/null)" != "$rev" ]; then
                    echo "hash: warning — HEAD differs from upstream, run push first" >&2
                fi
                echo "prefetching $owner_repo @ ''${rev:0:7} ..." >&2
                sha=$(nix-prefetch-url --unpack \
                    "https://github.com/$owner_repo/archive/$rev.tar.gz" 2>/dev/null)
                if [ -z "$sha" ]; then
                    echo "hash: prefetch failed (is $rev pushed to github?)" >&2
                    return 1
                fi
                sri=$(nix hash convert --hash-algo sha256 --to sri "$sha" 2>/dev/null \
                    || nix hash to-sri --type sha256 "$sha")
                echo "owner = \"''${owner_repo%%/*}\";"
                echo "repo = \"''${owner_repo##*/}\";"
                echo "rev = \"$rev\";"
                echo "hash = \"$sri\";"
            }

            # Silent fast-forward when possible.
            _auto_pull() {
                [ -n "$(git status --porcelain 2>/dev/null)" ] && return 0
                git fetch -q 2>/dev/null || return 0
                local behind
                behind=$(git rev-list --count HEAD..@{u} 2>/dev/null)
                [ -z "$behind" ] || [ "$behind" -eq 0 ] && return 0
                if git pull --ff-only -q >/dev/null 2>&1; then
                    echo "auto-pull: $behind new commit(s)"
                fi
            }

            # Once per entered repo.
            _git_enter_hook() {
                local top
                top=$(git rev-parse --show-toplevel 2>/dev/null)
                if [ -n "$top" ] && [ "$top" != "$_LAST_GIT_TOP" ]; then
                    _auto_pull
                fi
                _LAST_GIT_TOP=$top
            }
            PROMPT_COMMAND="_git_enter_hook''${PROMPT_COMMAND:+;$PROMPT_COMMAND}"

            # direnv loads only for nvim.
            nvim() {
                local top
                top=$(git rev-parse --show-toplevel 2>/dev/null)
                [ -n "$top" ] && _auto_pull
                if [ -n "$top" ] && [ -e "$top/flake.nix" ]; then
                    if [ ! -e "$top/.envrc" ]; then
                        printf 'use flake\n' > "$top/.envrc"
                        direnv allow "$top"
                    fi
                    direnv exec "$top" nvim "$@"
                else
                    command nvim "$@"
                fi
            }
          '';
        };
        direnv = {
          enable = true;
          # Only the nvim wrapper loads.
          enableBashIntegration = false;
          nix-direnv.enable = true;
          # Own repos never prompt.
          config.whitelist.prefix = [ "${config.home.homeDirectory}/git" ];
        };
      };
    }
  ;

  prompt =
    { pkgs, ... }:

    {

      programs.starship = {
        enable = true;
        enableBashIntegration = true;
      };

      home.file.".config/starship.toml".text = ''

    "$schema" = 'https://starship.rs/config-schema.json'

    format = """
    [](surface0)\
    $os\
    $username\
    [](bg:sapphire fg:surface0)\
    $directory\
    [](fg:sapphire bg:blue)\
    $git_branch\
    $git_status\
    [](fg:blue bg:lavender)\
    $c\
    $rust\
    $golang\
    $nodejs\
    $php\
    $java\
    $kotlin\
    $haskell\
    $python\
    [](fg:lavender bg:surface1)\
    $docker_context\
    [](fg:surface1 bg:surface1)\
    $time\
    [ ](fg:surface1)\
    $line_break$character"""

    palette = 'terminal'

    [palettes.gruvbox_dark]
    color_fg0 = '#fbf1c7'
    color_bg1 = '#3c3836'
    color_bg3 = '#665c54'
    color_blue = '#458588'
    color_aqua = '#689d6a'
    color_green = '#98971a'
    color_orange = '#d65d0e'
    color_purple = '#b16286'
    color_red = '#cc241d'
    color_yellow = '#d79921'

    # Follows the terminal palette.
    [palettes.terminal]
    text = "bright-white"
    base = "black"
    surface0 = "black"
    surface1 = "black"
    sapphire = "cyan"
    lavender = "purple"

    [os]
    disabled = true
    style = "bg:surface0 fg:text"

    [os.symbols]
    Windows = "󰍲"
    Ubuntu = "󰕈"
    SUSE = ""
    Raspbian = "󰐿"
    Mint = "󰣭"
    Macos = ""
    Manjaro = ""
    Linux = "󰌽"
    Gentoo = "󰣨"
    Fedora = "󰣛"
    Alpine = ""
    Amazon = ""
    Android = ""
    Arch = "󰣇"
    Artix = "󰣇"
    CentOS = ""
    Debian = "󰣚"
    Redhat = "󱄛"
    RedHatEnterprise = "󱄛"

    [username]
    show_always = true
    style_user = "bg:surface0 fg:text"
    style_root = "bg:surface0 fg:text"
    format = '[ $user ]($style)'

    [directory]
    style = "fg:base bg:sapphire"
    format = "[ $path ]($style)"
    truncation_length = 3
    truncation_symbol = "…/"

    [directory.substitutions]
    "Documents" = "󰈙 "
    "Downloads" = " "
    "Music" = "󰝚 "
    "Pictures" = " "
    "Developer" = "󰲋 "

    [git_branch]
    symbol = ""
    style = "bg:blue"
    format = '[[ $symbol $branch ](fg:base bg:blue)]($style)'

    [git_status]
    style = "bg:blue"
    format = '[[($all_status$ahead_behind )](fg:base bg:blue)]($style)'

    [nodejs]
    symbol = ""
    style = "bg:lavender"
    format = '[[ $symbol( $version) ](fg:base bg:lavender)]($style)'

    [c]
    symbol = " "
    style = "bg:lavender"
    format = '[[ $symbol( $version) ](fg:base bg:lavender)]($style)'

    [rust]
    symbol = ""
    style = "bg:lavender"
    format = '[[ $symbol( $version) ](fg:base bg:lavender)]($style)'

    [golang]
    symbol = ""
    style = "bg:lavender"
    format = '[[ $symbol( $version) ](fg:base bg:lavender)]($style)'

    [php]
    symbol = ""
    style = "bg:lavender"
    format = '[[ $symbol( $version) ](fg:base bg:lavender)]($style)'

    [java]
    symbol = " "
    style = "bg:lavender"
    format = '[[ $symbol( $version) ](fg:base bg:lavender)]($style)'

    [kotlin]
    symbol = ""
    style = "bg:lavender"
    format = '[[ $symbol( $version) ](fg:base bg:lavender)]($style)'

    [haskell]
    symbol = ""
    style = "bg:lavender"
    format = '[[ $symbol( $version) ](fg:base bg:lavender)]($style)'

    [python]
    symbol = ""
    style = "bg:lavender"
    format = '[[ $symbol( $version) ](fg:base bg:lavender)]($style)'

    [docker_context]
    symbol = ""
    style = "bg:surface1"
    format = '[[ $symbol( $context) ](fg:text bg:surface1)]($style)'

    [time]
    disabled = true
    time_format = "%R"
    style = "bg:surface1"
    format = '[[  $time ](fg:text bg:surface1)]($style)'

    [line_break]
    disabled = false

    [character]
    disabled = false
    success_symbol = '[](bold fg:green)'
    error_symbol = '[](bold fg:red)'
    vimcmd_symbol = '[](bold fg:creen)'
    vimcmd_replace_one_symbol = '[](bold fg:purple)'
    vimcmd_replace_symbol = '[](bold fg:purple)'
    vimcmd_visual_symbol = '[](bold fg:lavender)'
        '';

    }
  ;

  git =
    { pkgs, ... }:

    {

      home.packages = with pkgs; [
        libsecret
        git-lfs
      ];

      programs.git = {
        enable = true;
        package = pkgs.gitFull;
        signing.format = null;
        settings.user = {
          name = "aCeTotal";
          email = "lars.oksendal@gmail.com";
        };
      };

      programs.ssh = {
        enable = true;
        enableDefaultConfig = false;
        settings = {
          "*" = {
            Compression = true;
          };
          "github.com" = {
            IdentityFile = "~/.ssh/github";
          };
        };
      };
    }
  ;

  alacritty =
    { pkgs, ... }:

    {
      programs.alacritty.enable = true;

      home.packages = with pkgs; [
        nerd-fonts.jetbrains-mono
      ];


      home.file.".config/alacritty/alacritty.toml".text = ''

    general.import = [
      "~/.config/alacritty/catppuccin-mocha.toml",
      "~/.local/state/nixly-theme/alacritty.toml"
    ]

    [env]
    TERM = "xterm-256color"
    TERM_PROGRAM = "alacritty"

    [font]
    size = 14.0

    [font.bold]
    family = "JetBrainsMono Nerd Font"
    style = "Bold"

    [font.bold_italic]
    family = "JetBrainsMono Nerd Font"
    style = "Bold Italic"

    [font.italic]
    family = "JetBrainsMono Nerd Font"
    style = "Italic"

    [font.normal]
    family = "JetBrainsMono Nerd Font"
    style = "Regular"

    [window]
    dynamic_padding = true
    opacity = 0.75

    [selection]
    save_to_clipboard = true

    # Ctrl+Shift+C/V copy and paste.
    [[keyboard.bindings]]
    key = "C"
    mods = "Control|Shift"
    action = "Copy"

    [[keyboard.bindings]]
    key = "V"
    mods = "Control|Shift"
    action = "Paste"

    # Shift+Insert pastes the selection.
    [[keyboard.bindings]]
    key = "Insert"
    mods = "Shift"
    action = "PasteSelection"
        '';


      home.file.".config/alacritty/catppuccin-mocha.toml".text = ''
        [colors.primary]
        background = "#1E1E2E"
        foreground = "#CDD6F4"
        dim_foreground = "#CDD6F4"
        bright_foreground = "#CDD6F4"

        [colors.cursor]
        text = "#1E1E2E"
        cursor = "#F5E0DC"

        [colors.vi_mode_cursor]
        text = "#1E1E2E"
        cursor = "#B4BEFE"

        [colors.search.matches]
        foreground = "#1E1E2E"
        background = "#A6ADC8"

        [colors.search.focused_match]
        foreground = "#1E1E2E"
        background = "#A6E3A1"

        [colors.footer_bar]
        foreground = "#1E1E2E"
        background = "#A6ADC8"

        [colors.hints.start]
        foreground = "#1E1E2E"
        background = "#F9E2AF"

        [colors.hints.end]
        foreground = "#1E1E2E"
        background = "#A6ADC8"

        [colors.selection]
        text = "#1E1E2E"
        background = "#F5E0DC"

        [colors.normal]
        black = "#45475A"
        red = "#F38BA8"
        green = "#A6E3A1"
        yellow = "#F9E2AF"
        blue = "#89B4FA"
        magenta = "#F5C2E7"
        cyan = "#94E2D5"
        white = "#BAC2DE"

        [colors.bright]
        black = "#585B70"
        red = "#F38BA8"
        green = "#A6E3A1"
        yellow = "#F9E2AF"
        blue = "#89B4FA"
        magenta = "#F5C2E7"
        cyan = "#94E2D5"
        white = "#A6ADC8"
      '';


    }
  ;

  # Colours follow the wallpaper.
  theme =
    { config, lib, pkgs, ... }:

    let
      # Neutral dark until themed.
      fuzzelSeed = pkgs.writeText "fuzzel-dark.ini" ''
        [colors]
        background=1d2024ff
        text=e1e2e8ff
        message=c4c6cfff
        prompt=c4c6cfff
        placeholder=8e9099ff
        input=e1e2e8ff
        match=a1cafdff
        selection=3a4857ff
        selection-text=d6e3f7ff
        selection-match=a1cafdff
        counter=8e9099ff
        border=44474eff
      '';
    in
    {
      # Include targets exist before nixlytile.
      home.activation.nixlyTheme = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        d="${config.xdg.stateHome}/nixly-theme"
        run mkdir -p "$d"
        for f in foot.ini mpv.conf gtk.css alacritty.toml; do
          [ -e "$d/$f" ] || run touch "$d/$f"
        done
        [ -e "$d/fuzzel.ini" ] || run install -m644 ${fuzzelSeed} "$d/fuzzel.ini"
      '';

      programs.foot = {
        enable = true;
        settings.main.include = "~/.local/state/nixly-theme/foot.ini";
      };

      programs.fuzzel = {
        enable = true;
        settings.main.include = "~/.local/state/nixly-theme/fuzzel.ini";
      };

      programs.btop = {
        enable = true;
        settings = {
          color_theme = "nixly";
        };
      };
    };

  gtk =
    { config, pkgs, ... }:

    let
      adwDark = "${pkgs.adw-gtk3}/share/themes/adw-gtk3-dark";
      palette = "${config.xdg.stateHome}/nixly-theme/gtk.css";

      themeCss = gtk: extra: pkgs.writeText "nixly-${gtk}.css" ''
        @import url("file://${adwDark}/${gtk}/gtk.css");
        @import url("file://${palette}");
        ${extra}'';

      # adw-gtk3 hardcodes white here.
      gtk3Css = themeCss "gtk-3.0" ''
        button.suggested-action,
        button.suggested-action:hover,
        button.suggested-action:active,
        button.suggested-action:checked {
          color: @accent_fg_color;
        }
      '';
      # Replaces libadwaita's skipped providers.
      gtk4Css = themeCss "gtk-4.0" ''
        :root {
          --accent-bg-color: @accent_bg_color;
          --document-font-family: sans-serif;
          --monospace-font-family: monospace;
        }
      '';

      # Matugen flips gtk-theme between copies.
      theme = pkgs.linkFarm "nixly-gtk-theme" {
        "gtk-3.0/gtk.css" = gtk3Css;
        "gtk-3.0/gtk-dark.css" = gtk3Css;
        "gtk-4.0/gtk.css" = gtk4Css;
        "gtk-4.0/gtk-dark.css" = gtk4Css;
      };

      # libadwaita reloads only GTK_THEME.
      gtkTheme = "nixly-a:dark";
    in
    {
      home.pointerCursor = {
        enable = true;
        gtk.enable = true;
        package = pkgs.bibata-cursors;
        name = "Bibata-Modern-Ice";
        size = 21;
      };

      xdg.dataFile."themes/nixly-a".source = theme;
      xdg.dataFile."themes/nixly-b".source = theme;

      home.sessionVariables.GTK_THEME = gtkTheme;
      systemd.user.sessionVariables.GTK_THEME = gtkTheme;

      gtk = {
        enable = true;
        theme.name = "nixly-a";
        # GTK2 has no nixly theme.
        gtk2.theme = {
          name = "Adwaita-dark";
          package = pkgs.gnome-themes-extra;
        };
        gtk4.theme = null;
        iconTheme = {
          name = "Papirus-Dark";
          package = pkgs.papirus-icon-theme;
        };
        gtk3.extraConfig = {
          "gtk-enable-tooltips" = 1;
          "gtk-tooltip-timeout" = 10;
          "gtk-tooltip-browse-timeout" = 10;
          "gtk-tooltip-browse-mode-timeout" = 10;
        };
        gtk4.extraConfig = {
          "gtk-enable-tooltips" = 1;
          "gtk-tooltip-timeout" = 10;
          "gtk-tooltip-browse-timeout" = 10;
          "gtk-tooltip-browse-mode-timeout" = 10;
        };
      };
    }
  ;

  qt =
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
      home.packages = [
        (pkgs.runCommand "nixly-kdeglobals" { } ''
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
        '')
      ];

      # Written by nixlytile's wallpaper theme.
      xdg.configFile."kdeglobals".source =
        config.lib.file.mkOutOfStoreSymlink "${config.xdg.stateHome}/nixly-theme/kdeglobals-colors";
    }
  ;
in
{
  home-manager.users.${nixlyUser}.imports = [
    base
    bash
    prompt
    git
    alacritty
    theme
    gtk
    qt
  ];
}
$nix$),
('gaming', 'Spill', 'Steam, Proton, GeForce NOW, kontrollere, spillmodus og emulatorer.', false, 7, $nix${ config, lib, pkgs, hwData, nixlyUser, ... }:

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
    hardware.xpadneo.enable = true;
    hardware.xone.enable = true;

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
$nix$),
('apps', 'Programmer', 'Nettleser, media, kontor, RSS og tekstnettleser.', false, 8, $nix${ lib, ... }:

let
  # Drops packages the platform lacks.
  everyday = {
    home-manager.sharedModules = [
      ({ pkgs, ... }: {
        home.packages = builtins.filter
          (lib.meta.availableOn pkgs.stdenv.hostPlatform)
          (with pkgs; [
            brave
            discord
            google-chrome
            libreoffice-fresh
            nixlymedia
            pavucontrol
            spotify
            teams-for-linux
            vlc
          ]);
      })
    ];
  };

  # Browsing plus Shields only.
  browser = {
    environment.etc."brave/policies/managed/lean.json".text = builtins.toJSON {
      BackgroundModeEnabled = false;
      DefaultBrowserSettingEnabled = false;
      MetricsReportingEnabled = false;
      PromotionsEnabled = false;
      BraveAIChatEnabled = false;
      BraveLocalAIEnabled = false;
      BraveNewsDisabled = true;
      BraveP3AEnabled = false;
      BravePlaylistEnabled = false;
      BraveRewardsDisabled = true;
      BraveSpeedreaderEnabled = false;
      BraveStatsPingEnabled = false;
      BraveTalkDisabled = true;
      BraveVPNDisabled = true;
      BraveWalletDisabled = true;
      BraveWaybackMachineEnabled = false;
      BraveWebDiscoveryEnabled = false;
      TorDisabled = true;
      TranslateEnabled = false;
      HardwareAccelerationModeEnabled = true;
      # Blank tab on start.
      RestoreOnStartup = 5;
      DefaultSearchProviderEnabled = true;
      DefaultSearchProviderName = "Google";
      DefaultSearchProviderKeyword = "google.com";
      DefaultSearchProviderSearchURL = "https://www.google.com/search?q={searchTerms}";
      DefaultSearchProviderSuggestURL = "https://www.google.com/complete/search?client=chrome&q={searchTerms}";
    };

    home-manager.sharedModules = [
      {
        xdg.mimeApps = {
          enable = true;
          defaultApplications = {
            "text/html" = [ "brave-browser.desktop" ];
            "x-scheme-handler/http" = [ "brave-browser.desktop" ];
            "x-scheme-handler/https" = [ "brave-browser.desktop" ];
          };
        };
      }
    ];
  };

  feeds =
    { pkgs, ... }:

    {
      config.home-manager.sharedModules = [
        {
          programs.newsboat = {
            enable = true;

            extraConfig = ''
              # Catppuccin Mocha colours
              color background          color236  default
              color listnormal          color7    default
              color listnormal_unread   color4    default   bold
              color listfocus           color0    color4
              color listfocus_unread    color0    color4    bold
              color info                color0    color5    bold
              color article             color7    default
              color hint-key            color3    default   bold
              color hint-keys-delimiter color8    default
              color hint-separator      color8    default
              color title               color5    default   bold
              color end-of-text-marker  color8    default

              # Highlight for article content
              highlight article "^Feed:.*"        color5  default bold
              highlight article "^Title:.*"       color4  default bold
              highlight article "^Author:.*"      color3  default
              highlight article "^Date:.*"        color6  default
              highlight article "^Link:.*"        color6  default underline
              highlight article "\\[image\\ [0-9]+.*\\]" color8 default
              highlight article "\\[link\\ [0-9]+\\]"    color6 default underline
              highlight article "https?://[^ ]+"  color6  default underline

              # Highlight in the feed list
              highlight feedlist "linux"           color2  default bold
              highlight feedlist "valve|steam|proton" color4 default bold
              highlight feedlist "tech"            color5  default bold

              # Formatting
              feedlist-format     "%?T?%-14T ?%t %> %U/%c "
              articlelist-format  "%D  %?T?%-12T  ?%t %> %L"
              datetime-format     "%d/%m"
              feedlist-title-format "  Feeds (%u uleste, %t totalt)%?T? - %T?"
              articlelist-title-format "  %T (%u uleste)%?F? - %F?"
              searchresult-title-format "  Sok - %s (%u uleste)"
              filebrowser-title-format "%?O?Lagre fil:&Apne fil:? %f"
              itemview-title-format "  %T"

              text-width 90

              # Behaviour
              auto-reload yes
              reload-time 30
              reload-threads 4
              prepopulate-query-feeds yes
              show-read-feeds yes
              show-read-articles no
              confirm-mark-feed-read no
              cleanup-on-quit yes
              max-items 200

              # Browser
              browser "xdg-open %u"
              macro o set browser "xdg-open %u" ; open-in-browser ; set browser "xdg-open %u"
              macro v set browser "mpv %u" ; open-in-browser ; set browser "xdg-open %u"

              # Vim keybindings
              bind-key j down
              bind-key k up
              bind-key J next-feed articlelist
              bind-key K prev-feed articlelist
              bind-key g home
              bind-key G end
              bind-key l open
              bind-key h quit
              bind-key n next-unread
              bind-key N prev-unread
              bind-key u show-urls
              bind-key SPACE toggle-article-read
              bind-key ^D pagedown
              bind-key ^U pageup
              bind-key d toggle-show-read-feeds
              bind-key D delete-article
              bind-key ^R reload-all
            '';

            urls = [
              # Linux news
              { url = "https://www.phoronix.com/rss.php"; tags = [ "linux" "hardware" ]; title = "Phoronix"; }
              { url = "https://lwn.net/headlines/rss"; tags = [ "linux" "kernel" ]; title = "LWN.net"; }
              { url = "https://www.omgubuntu.co.uk/feed"; tags = [ "linux" "ubuntu" ]; title = "OMG! Ubuntu"; }
              { url = "https://www.gamingonlinux.com/article_rss.php"; tags = [ "linux" "gaming" ]; title = "GamingOnLinux"; }
              { url = "https://linuxgamingcentral.com/index.xml"; tags = [ "linux" "gaming" ]; title = "Linux Gaming Central"; }
              { url = "https://itsfoss.com/feed/"; tags = [ "linux" ]; title = "It's FOSS"; }
              { url = "https://9to5linux.com/feed"; tags = [ "linux" ]; title = "9to5Linux"; }
              { url = "https://www.linuxtoday.com/feed/"; tags = [ "linux" ]; title = "Linux Today"; }
              { url = "https://tuxphones.com/rss/"; tags = [ "linux" "mobile" ]; title = "TuxPhones"; }
              { url = "https://thisweek.gnome.org/index.xml"; tags = [ "linux" "gnome" ]; title = "This Week in GNOME"; }
              { url = "https://pointieststick.com/feed/"; tags = [ "linux" "kde" ]; title = "This Week in KDE (Nate)"; }
              { url = "https://blog.torproject.org/feed/"; tags = [ "linux" "privacy" ]; title = "Tor Project"; }
              { url = "https://fedoramagazine.org/feed/"; tags = [ "linux" "fedora" ]; title = "Fedora Magazine"; }
              { url = "https://archlinux.org/feeds/news/"; tags = [ "linux" "arch" ]; title = "Arch Linux News"; }
              { url = "https://weekly.nixos.org/feeds/all.rss.xml"; tags = [ "linux" "nix" ]; title = "NixOS Weekly"; }
              { url = "https://discourse.nixos.org/c/announcements/8.rss"; tags = [ "linux" "nix" ]; title = "NixOS Announcements"; }
              { url = "https://planet.kernel.org/rss20.xml"; tags = [ "linux" "kernel" ]; title = "Planet Kernel"; }

              # Valve, Steam and Proton
              { url = "https://store.steampowered.com/feeds/news/app/593110"; tags = [ "valve" "steam" ]; title = "Steam Deck News"; }
              { url = "https://store.steampowered.com/feeds/news/app/1493710"; tags = [ "valve" "proton" ]; title = "Proton Experimental"; }
              { url = "https://store.steampowered.com/feeds/news/app/2180100"; tags = [ "valve" "proton" ]; title = "Proton Hotfix"; }
              { url = "https://store.steampowered.com/feeds/news/app/2805730"; tags = [ "valve" "deadlock" ]; title = "Deadlock"; }
              { url = "https://store.steampowered.com/feeds/news/app/730"; tags = [ "valve" "cs2" ]; title = "Counter-Strike 2"; }
              { url = "https://store.steampowered.com/feeds/news/app/570"; tags = [ "valve" "dota2" ]; title = "Dota 2"; }
              { url = "https://www.valvesoftware.com/en/blog?feed=rss"; tags = [ "valve" ]; title = "Valve Blog"; }
              { url = "https://boilingsteam.com/feed/"; tags = [ "valve" "linux" "gaming" ]; title = "Boiling Steam"; }

              # Tech news
              { url = "https://arstechnica.com/feed/"; tags = [ "tech" ]; title = "Ars Technica"; }
              { url = "https://www.theverge.com/rss/index.xml"; tags = [ "tech" ]; title = "The Verge"; }
              { url = "https://techcrunch.com/feed/"; tags = [ "tech" ]; title = "TechCrunch"; }
              { url = "https://www.anandtech.com/rss/"; tags = [ "tech" "hardware" ]; title = "AnandTech"; }
              { url = "https://feeds.arstechnica.com/arstechnica/gadgets"; tags = [ "tech" "hardware" ]; title = "Ars Technica Hardware"; }
              { url = "https://www.tomshardware.com/feeds/all"; tags = [ "tech" "hardware" ]; title = "Tom's Hardware"; }
              { url = "https://hackaday.com/feed/"; tags = [ "tech" "diy" ]; title = "Hackaday"; }
              { url = "https://news.ycombinator.com/rss"; tags = [ "tech" ]; title = "Hacker News"; }
              { url = "https://lobste.rs/rss"; tags = [ "tech" "programming" ]; title = "Lobsters"; }
              { url = "https://www.wired.com/feed/rss"; tags = [ "tech" ]; title = "Wired"; }
              { url = "https://www.bleepingcomputer.com/feed/"; tags = [ "tech" "security" ]; title = "BleepingComputer"; }
              { url = "https://krebsonsecurity.com/feed/"; tags = [ "tech" "security" ]; title = "Krebs on Security"; }
              { url = "https://www.schneier.com/feed/atom/"; tags = [ "tech" "security" ]; title = "Schneier on Security"; }
              { url = "https://www.servethehome.com/feed/"; tags = [ "tech" "server" ]; title = "ServeTheHome"; }
              { url = "https://selfhosted.show/rss"; tags = [ "tech" "selfhost" ]; title = "Self-Hosted Podcast"; }
              { url = "https://blog.cloudflare.com/rss/"; tags = [ "tech" "web" ]; title = "Cloudflare Blog"; }

              # GPUs
              { url = "https://videocardz.com/feed"; tags = [ "tech" "gpu" ]; title = "VideoCardz"; }
              { url = "https://www.nvidia.com/en-us/drivers/unix/feed.xml"; tags = [ "tech" "gpu" "nvidia" ]; title = "NVIDIA Unix Drivers"; }

              # Open source
              { url = "https://github.blog/feed/"; tags = [ "tech" "foss" ]; title = "GitHub Blog"; }
              { url = "https://www.opensourceforu.com/feed/"; tags = [ "tech" "foss" ]; title = "Open Source For You"; }
            ];
          };
        }
      ];
    }
  ;

  textBrowser =
    { ... }:

    {
      config.home-manager.sharedModules = [
        ({ pkgs, ... }: {
          home.packages = with pkgs; [ w3m ];

          # w3m ignores XDG.
          home.file.".w3m/config".text = ''
            # Charset
            display_charset UTF-8
            document_charset UTF-8
            system_charset UTF-8
            auto_detect 2

            # Display
            color 1
            ansi_color 1
            use_mouse 1
            clear_buffer 1
            decode_cte 1
            fold_textarea 1
            display_image 0
            pseudo_inlines 1
            tabstop 4
            indent_incr 2

            # Navigation
            nextpage_topline 1
            label_topline 1
            emacs_like_lineedit 1
            vi_prec_num 1

            # Cookies / cache
            use_cookie 1
            accept_cookie 1
            accept_bad_cookie 0
            cookie_avoid_wrong_number_of_dots ""
            show_cookie 0

            # Tabs
            open_tab_blank 1
            open_tab_dl_list 1
            close_tab_back 1

            # Forms
            confirm_qq 0
            target_self 1

            # Downloads land in PWD.
            download_dir .
            decode_cte 1
            auto_uncompress 1

            # Editor / pager
            editor nvim

            # M: open, wget, copy.
            extbrowser  sh -c 'xdg-open "%s" &'
            extbrowser2 sh -c 'wget --content-disposition -- "%s"'
            extbrowser3 sh -c 'echo -n "%s" | wl-copy'
            mailto_options 0

            # SSL
            ssl_verify_server 1
            ssl_ca_file /etc/ssl/certs/ca-certificates.crt

            # Search
            case_sensitive 0
            wrap_search 1
          '';

          # Vim-like keymap.
          home.file.".w3m/keymap".text = ''
            # Movement
            keymap  j         MOVE_DOWN
            keymap  k         MOVE_UP
            keymap  h         MOVE_LEFT
            keymap  l         MOVE_RIGHT
            keymap  g         BEGIN
            keymap  G         END
            keymap  C-f       NEXT_PAGE
            keymap  C-b       PREV_PAGE
            keymap  C-d       NEXT_HALF_PAGE
            keymap  C-u       PREV_HALF_PAGE
            keymap  H         LINE_BEGIN
            keymap  L         LINE_END

            # Cycle through links
            keymap  TAB       NEXT_LINK
            keymap  C-n       NEXT_LINK
            keymap  ESC-TAB   PREV_LINK
            keymap  C-p       PREV_LINK

            # Follow link or submit form
            keymap  RET       GOTO_LINK
            keymap  SPC       NEXT_PAGE

            # History
            keymap  u         BACK
            keymap  C-h       HISTORY
            keymap  U         GOTO
            keymap  r         RELOAD
            keymap  R         RELOAD

            # In-page search
            keymap  /         SEARCH
            keymap  ?         SEARCH_BACK
            keymap  n         SEARCH_NEXT
            keymap  N         SEARCH_PREV

            # Tabs
            keymap  t         NEW_TAB
            keymap  T         TAB_LINK
            keymap  C-w       CLOSE_TAB
            keymap  ]         NEXT_TAB
            keymap  [         PREV_TAB
            keymap  }         NEXT_TAB
            keymap  {         PREV_TAB

            # Save link, page, queue.
            keymap  a         SAVE_LINK
            keymap  s         SAVE
            keymap  d         DOWNLOAD_LIST
            # Open, wget, copy URL.
            keymap  M         EXTERN

            # Bookmarks
            keymap  B         BOOKMARK
            keymap  M-b       ADD_BOOKMARK

            # Misc
            keymap  o         OPTIONS
            keymap  v         VIEW
            keymap  =         INFO
            keymap  C-l       REDRAW
            keymap  q         EXIT
            keymap  Q         EXIT
            keymap  :         COMMAND
            keymap  M-h       HELP

            # URL to clipboard
            keymap  y         PIPE_BUF
            keymap  Y         PIPE_SHELL
          '';

          home.file.".w3m/mailcap".text = ''
            image/*;             swayimg %s
            video/*;             mpv %s
            audio/*;             mpv %s
            application/pdf;     nixly-pdf %s
          '';
        })
      ];
    }
  ;

  images =
    # Swayimg opens images.
    { ... }:

    {
      config.home-manager.sharedModules = [
        ({ pkgs, ... }: {
          home.packages = with pkgs; [
            swayimg
          ];

          xdg.mimeApps = {
            enable = true;
            defaultApplications = {
              # Formats swayimg declares.
              "image/avif" = [ "swayimg.desktop" ];
              "image/bmp" = [ "swayimg.desktop" ];
              "image/gif" = [ "swayimg.desktop" ];
              "image/heif" = [ "swayimg.desktop" ];
              "image/jpeg" = [ "swayimg.desktop" ];
              "image/jpg" = [ "swayimg.desktop" ];
              "image/jxl" = [ "swayimg.desktop" ];
              "image/pbm" = [ "swayimg.desktop" ];
              "image/pjpeg" = [ "swayimg.desktop" ];
              "image/png" = [ "swayimg.desktop" ];
              "image/svg+xml" = [ "swayimg.desktop" ];
              "image/tiff" = [ "swayimg.desktop" ];
              "image/webp" = [ "swayimg.desktop" ];
              "image/x-bmp" = [ "swayimg.desktop" ];
              "image/x-exr" = [ "swayimg.desktop" ];
              "image/x-png" = [ "swayimg.desktop" ];
              "image/x-portable-anymap" = [ "swayimg.desktop" ];
              "image/x-portable-bitmap" = [ "swayimg.desktop" ];
              "image/x-portable-graymap" = [ "swayimg.desktop" ];
              "image/x-portable-pixmap" = [ "swayimg.desktop" ];
              "image/x-targa" = [ "swayimg.desktop" ];
              "image/x-tga" = [ "swayimg.desktop" ];
            };
          };
        })
      ];
    }
  ;

  video =
    { ... }:

    {
      config.home-manager.sharedModules = [
        ({ pkgs, ... }: {
          programs.mpv = {
            enable = true;
            package = pkgs.mpv;

            # Synced to the display rate.
            config = {
              # Wallpaper-themed OSD and uosc.
              include = "~/.local/state/nixly-theme/mpv.conf";
              # Best quality on modern GPUs.
              vo = "gpu-next";
              gpu-api = "vulkan";
              hwdec = "auto-safe";
              hwdec-codecs = "all";

              video-sync = "display-resample";
              interpolation = true;
              tscale = "oversample";
              # Free input lag win.
              video-latency-hacks = true;

              profile = "high-quality";
              scale = "ewa_lanczossharp";
              cscale = "ewa_lanczossharp";
              dscale = "mitchell";
              dither-depth = "auto";
              deband = true;
              deband-iterations = 2;
              deband-threshold = 35;
              deband-range = 16;
              deband-grain = 4;

              target-colorspace-hint = true;
              # HDR on SDR screens.
              tone-mapping = "bt.2446a";
              hdr-compute-peak = true;

              audio-channels = "auto-safe";
              audio-spdif = "ac3,dts,eac3,dts-hd,truehd";
              audio-exclusive = false;
              af = "scaletempo2";
              volume = 100;
              volume-max = 150;

              sub-auto = "fuzzy";
              sub-file-paths = "subs:subtitles:Subs";
              slang = "no,nob,nor,en,eng";
              alang = "no,nob,nor,jpn,en,eng";
              sub-font = "Noto Sans";
              sub-font-size = 42;
              sub-border-size = 2;
              sub-shadow-offset = 1;

              cache = true;
              cache-secs = 60;
              demuxer-max-bytes = "512MiB";
              demuxer-max-back-bytes = "256MiB";
              demuxer-readahead-secs = 30;

              keep-open = "yes";
              save-position-on-quit = true;
              watch-later-options-remove = "pause";
              screenshot-format = "png";
              screenshot-directory = "~/Pictures/mpv";

              osd-bar = true;
              osd-font = "JetBrainsMono Nerd Font";
              osd-font-size = 28;

              ytdl-format = "bestvideo[height<=?2160][vcodec!=?vp9]+bestaudio/best";
              script-opts = "ytdl_hook-ytdl_path=${pkgs.yt-dlp}/bin/yt-dlp";
            };

            # Auto-activated on match.
            profiles = {
              # mpv --profile=tv.
              "tv" = {
                profile-desc = "TV / HTPC playback";
                fullscreen = true;
                interpolation = true;
                tscale = "oversample";
                video-sync = "display-resample";
                deband = true;
                tone-mapping = "bt.2446a";
                hdr-compute-peak = true;
              };

              "high-res" = {
                profile-desc = "auto profile for >=1440p";
                profile-cond = "(width or 0) >= 1440";
                scale = "ewa_lanczos";
                cscale = "ewa_lanczos";
                deband = false;
              };

              "low-res" = {
                profile-desc = "auto profile for <720p";
                profile-cond = "(width or 0) < 1280";
                scale = "ewa_lanczossharp";
                cscale = "ewa_lanczossharp";
                deband = true;
              };

              "anime" = {
                profile-desc = "Anime tuning";
                profile-cond = "string.match(p.filename, '%.[Aa]nime') ~= nil";
                deband = true;
                deband-iterations = 4;
                deband-grain = 24;
                scale = "ewa_lanczossharp";
                cscale = "mitchell";
              };
            };

            bindings = {
              "RIGHT" = "seek 5";
              "LEFT" = "seek -5";
              "UP" = "seek 60";
              "DOWN" = "seek -60";
              "Shift+RIGHT" = "seek 30";
              "Shift+LEFT" = "seek -30";

              "[" = "multiply speed 0.9091";
              "]" = "multiply speed 1.1";
              "BS" = "set speed 1.0";

              "WHEEL_UP" = "add volume 5";
              "WHEEL_DOWN" = "add volume -5";
              "m" = "cycle mute";

              "j" = "cycle sub";
              "J" = "cycle sub down";
              "#" = "cycle audio";

              "f" = "cycle fullscreen";
              "TAB" = "cycle ontop";
              "i" = "script-binding stats/display-stats-toggle";
              "I" = "script-binding stats/display-stats";
              "p" = "cycle pause";
              "q" = "quit-watch-later";
              "Q" = "quit";

              "Ctrl+t" = "apply-profile tv";

              "." = "frame-step";
              "," = "frame-back-step";

              "s" = "screenshot";
              "S" = "screenshot video";
            };

            scripts = with pkgs.mpvScripts; [
              mpris # MPRIS for media-keys / control center
              thumbfast # Hurtig thumbnail-preview ved seeking
              autoload # Auto-load neste fil i mappa
              uosc # Moderne OSC/UI
              quality-menu # YouTube quality picker
            ];
          };

          # Streaming needs yt-dlp.
          home.packages = with pkgs; [
            yt-dlp
          ];
        })
      ];
    }
  ;
in
{
  imports = [
    everyday
    browser
    feeds
    textBrowser
    images
    video
  ];
}
$nix$),
('desktop', 'Desktop', 'Kun desktop og laptop: Citrix, Claude Code, Blender, FreeCAD, Gaea, Unreal, RetroArch, kalkulator og PDF.', false, 9, $nix${ config, lib, pkgs, hwData, nixlyUser, ... }:

let
  x86 = hwData.platform.arch == "x86_64";

  # Calculator, PDF and FreeCAD.
  tools =
    { pkgs, lib, ... }:

    let
      freecad = pkgs.freecad.customize {
        modules = [ "${pkgs.freecad-mcp}/share/freecad-mcp/FreeCADMCP" ];
      };
      server = builtins.toJSON {
        type = "stdio";
        command = lib.getExe pkgs.freecad-mcp;
        args = [ ];
      };
    in
    {
      home.packages = [ pkgs.nixly_kalk pkgs.nixly_pdf freecad pkgs.freecad-mcp ];

      # Nixly-PDF opens every PDF.
      xdg.mimeApps = {
        enable = true;
        defaultApplications."application/pdf" = [ "nixly-pdf.desktop" ];
        associations.removed."application/pdf" = [
          "draw.desktop"
          "brave-browser.desktop"
          "com.brave.Browser.desktop"
        ];
      };

      # Merged into mutable ~/.claude.json.
      home.activation.claudeFreecadMcp = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        f="$HOME/.claude.json"
        [ -s "$f" ] || echo '{}' > "$f"
        if ! ${lib.getExe pkgs.jq} -e --argjson s '${server}' '.mcpServers.freecad == $s' "$f" >/dev/null; then
          t=$(mktemp "$f.XXXXXX")
          ${lib.getExe pkgs.jq} --argjson s '${server}' '.mcpServers.freecad = $s' "$f" > "$t"
          mv "$t" "$f"
        fi
      '';
    };

  terrain = { pkgs, ... }: {
    home.packages = [ pkgs.gaea ];
  };

  # Built from the Wayland fork.
  unreal =
    let
      workspace = "/var/cache/ue5";
    in
    {
      options.nixlyos.ue5.enable = lib.mkEnableOption "Unreal Engine 5 built from the Wayland fork";

      config = lib.mkIf config.nixlyos.ue5.enable {
        environment.systemPackages = [ pkgs.ue5_source ];

        # Incremental UBT tree for nixbld.
        nix.settings.extra-sandbox-paths = [ workspace ];
        systemd.tmpfiles.rules = [ "d ${workspace} 2770 root nixbld -" ];
      };
    };

  # The desktop's own cards.
  speakers = {
    xdg.configFile."wireplumber/wireplumber.conf.d/51-audio-priority.conf".text = ''
      monitor.alsa.rules = [
        {
          matches = [
            { device.name = "alsa_card.pci-0000_00_1f.3" }
          ]
          actions = {
            update-props = {
              api.acp.auto-profile = true
              api.acp.auto-port = true
            }
          }
        }
        {
          matches = [
            { device.name = "alsa_card.pci-0000_04_00.0" }
          ]
          actions = {
            update-props = {
              api.acp.auto-profile = false
              device.profile = "output:hdmi-surround71"
            }
          }
        }
        {
          matches = [
            { node.name = "~alsa_output\\.pci-0000_00_1f\\.3\\..*" }
          ]
          actions = {
            update-props = {
              priority.session = 3000
              priority.driver = 3000
            }
          }
        }
        {
          matches = [
            { node.name = "~alsa_output\\.pci-0000_04_00\\.0\\..*" }
          ]
          actions = {
            update-props = {
              priority.session = 2000
              priority.driver = 2000
            }
          }
        }
      ]
    '';
  };

  # HTPC ships its own.
  emulation =
    { pkgs, lib, nixlyUser, ... }:

    {
      environment.systemPackages = with pkgs; [
        # Skips cores ARM lacks.
        (retroarch.withCores (cores: builtins.filter (lib.meta.availableOn stdenv.hostPlatform) [
          # N64
          cores.mupen64plus
          cores.parallel-n64

          # NES
          cores.nestopia
          cores.fceumm

          # SNES
          cores.snes9x
          cores.bsnes

          cores.genesis-plus-gx # Mega Drive / SMS / Game Gear
          cores.gambatte # GB / GBC
          cores.mgba # GBA
          cores.beetle-psx-hw # PlayStation 1 (Vulkan/HW)
        ]))

        retroarch-assets # XMB icons, fonts, menu assets
        retroarch-joypad-autoconfig
      ];

      home-manager.users.${nixlyUser} = { lib, ... }: {
        home.activation.retroarchConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          RA_CFG_DIR="$HOME/.config/retroarch"
          mkdir -p "$RA_CFG_DIR"
          mkdir -p "$RA_CFG_DIR/cores"
          mkdir -p "$RA_CFG_DIR/system"
          mkdir -p "$RA_CFG_DIR/saves"
          mkdir -p "$RA_CFG_DIR/states"
          mkdir -p "$RA_CFG_DIR/screenshots"
          mkdir -p "$RA_CFG_DIR/playlists"
          mkdir -p "$RA_CFG_DIR/thumbnails"

          cat > "$RA_CFG_DIR/retroarch.cfg" << 'RACFG'
          # Menu / theme
          menu_driver = "xmb"
          # Monochrome icon pack.
          menu_xmb_theme = "0"
          menu_xmb_menu_color_theme = "1"
          menu_xmb_shadows_enable = "true"
          menu_xmb_ribbon_enable = "1"
          menu_horizontal_animation = "true"
          menu_show_load_core = "true"
          menu_show_load_content = "true"
          menu_show_online_updater = "true"
          menu_show_core_updater = "true"
          menu_enable_widgets = "true"
          menu_widget_scale_auto = "true"
          rgui_show_start_screen = "false"
          quick_menu_show_save_load_state = "true"
          quick_menu_show_take_screenshot = "true"

          # Per-system XMB wallpapers.
          menu_dynamic_wallpaper_enable = "true"
          dynamic_wallpapers_directory = "${pkgs.retroarch-assets}/share/retroarch/assets/wallpapers"

          # Boxart right, snap left.
          menu_thumbnails = "3"
          menu_left_thumbnails = "2"
          menu_rgui_thumbnail_downscaler = "1"
          playlist_show_sublabels = "true"

          assets_directory = "${pkgs.retroarch-assets}/share/retroarch/assets"
          xmb_font = ""

          # Video
          video_driver = "vulkan"
          video_fullscreen = "true"
          # Covers the layer-shell top.
          video_windowed_fullscreen = "false"
          video_vsync = "true"
          video_threaded = "true"
          video_smooth = "true"
          video_scale_integer = "false"
          video_aspect_ratio_auto = "true"
          # Pure vsync, no VRR.
          video_max_swapchain_images = "3"
          video_frame_delay = "0"
          video_frame_delay_auto = "true"
          video_hard_sync = "false"
          vrr_runloop_enable = "false"
          fastforward_ratio = "0.0"
          video_shader_enable = "true"
          video_shader_dir = "~/.config/retroarch/shaders"

          # Audio
          audio_driver = "pipewire"
          audio_enable = "true"
          audio_sync = "true"
          audio_volume = "0.0"

          # Input / controllers
          input_driver = "udev"
          input_joypad_driver = "udev"
          input_autodetect_enable = "true"
          input_auto_remaps_enable = "true"
          input_max_users = "4"
          input_menu_toggle_gamepad_combo = "4"   # L3 + R3 → menu
          input_overlay_enable = "false"
          input_bluetooth_driver = "bluez"

          joypad_autoconfig_dir = "${pkgs.retroarch-joypad-autoconfig}/share/libretro/autoconfig"

          # Core / content paths
          libretro_directory = "~/.config/retroarch/cores"
          libretro_info_path = "~/.config/retroarch/cores"
          system_directory = "~/.config/retroarch/system"
          savefile_directory = "~/.config/retroarch/saves"
          savestate_directory = "~/.config/retroarch/states"
          screenshot_directory = "~/.config/retroarch/screenshots"
          playlist_directory = "~/.config/retroarch/playlists"
          thumbnails_directory = "~/.config/retroarch/thumbnails"

          # In-app updater fetches assets.
          network_on_demand_thumbnails = "true"
          core_updater_buildbot_url = "https://buildbot.libretro.com/nightly/linux/${pkgs.stdenv.hostPlatform.linuxArch}/latest/"
          core_updater_buildbot_assets_url = "https://buildbot.libretro.com/assets/"
          core_updater_auto_extract_archive = "true"
          core_updater_show_experimental_cores = "false"
          menu_show_core_updater = "true"
          automatically_add_content_to_playlist = "true"

          # Misc
          pause_nonactive = "false"
          check_firmware_before_loading = "false"
          auto_screenshot_filename = "true"
          savestate_auto_save = "true"
          savestate_auto_load = "true"
          config_save_on_exit = "true"
          RACFG

          # Every core fills 16:9.
          mkdir -p "$RA_CFG_DIR/config"

          for core in \
            "bsnes" "Snes9x" "FCEUmm" "Nestopia" \
            "Gambatte" "mGBA" "Genesis Plus GX" \
            "Mupen64Plus-Next" "ParaLLEl N64" "Beetle PSX HW"; do
            mkdir -p "$RA_CFG_DIR/config/$core"
            cat > "$RA_CFG_DIR/config/$core/$core.cfg" << 'CORECFG'
          aspect_ratio_index = "1"
          video_fullscreen = "true"
          video_windowed_fullscreen = "false"
          video_fullscreen_x = "0"
          video_fullscreen_y = "0"
          video_smooth = "true"
          video_force_aspect = "true"
          video_scale_integer = "false"
          CORECFG
          done

          # Keeps in-app tweaks to other keys.
          upsert_opt() {
            local file="$1" key="$2" value="$3"
            mkdir -p "$(dirname "$file")"
            touch "$file"
            if grep -q "^$key = " "$file" 2>/dev/null; then
              sed -i "s|^$key = .*|$key = \"$value\"|" "$file"
            else
              echo "$key = \"$value\"" >> "$file"
            fi
          }

          # Mupen64Plus-Next widescreen hack.
          M64="$RA_CFG_DIR/config/Mupen64Plus-Next/Mupen64Plus-Next.opt"
          upsert_opt "$M64" "mupen64plus-aspect" "16:9 adjusted"
          upsert_opt "$M64" "mupen64plus-169screensize" "1920x1080"
          upsert_opt "$M64" "mupen64plus-parallel-rdp-upscaling" "4x"
          upsert_opt "$M64" "mupen64plus-MultiSampling" "4"
          upsert_opt "$M64" "mupen64plus-Framerate" "Original"

          # ParaLLEl N64 widescreen, 4x.
          PN64="$RA_CFG_DIR/config/ParaLLEl N64/ParaLLEl N64.opt"
          upsert_opt "$PN64" "parallel-n64-aspectratiohint" "widescreen"
          upsert_opt "$PN64" "parallel-n64-screensize" "1920x1080"
          upsert_opt "$PN64" "parallel-n64-parallel-rdp-upscaling" "4x"
          upsert_opt "$PN64" "parallel-n64-framerate" "original"

          # Beetle PSX widescreen, 4x, PGXP.
          BPSX="$RA_CFG_DIR/config/Beetle PSX HW/Beetle PSX HW.opt"
          upsert_opt "$BPSX" "beetle_psx_hw_renderer" "hardware"
          upsert_opt "$BPSX" "beetle_psx_hw_renderer_software_fb" "enabled"
          upsert_opt "$BPSX" "beetle_psx_hw_internal_resolution" "4x"
          upsert_opt "$BPSX" "beetle_psx_hw_widescreen_hack" "enabled"
          upsert_opt "$BPSX" "beetle_psx_hw_widescreen_hack_aspect_ratio" "16:9"
          upsert_opt "$BPSX" "beetle_psx_hw_filter" "bilinear"
          upsert_opt "$BPSX" "beetle_psx_hw_dither_mode" "internal resolution"
          upsert_opt "$BPSX" "beetle_psx_hw_msaa" "4x"
          upsert_opt "$BPSX" "beetle_psx_hw_pgxp_mode" "memory only"
          upsert_opt "$BPSX" "beetle_psx_hw_pgxp_vertex" "enabled"
          upsert_opt "$BPSX" "beetle_psx_hw_pgxp_texture" "enabled"
          upsert_opt "$BPSX" "beetle_psx_hw_adaptive_smoothing" "enabled"
          upsert_opt "$BPSX" "beetle_psx_hw_cpu_freq_scale" "100%(native)"
          upsert_opt "$BPSX" "beetle_psx_hw_skip_bios" "enabled"
          upsert_opt "$BPSX" "beetle_psx_hw_frame_duping" "enabled"

          # bsnes HD Mode 7.
          BSNES="$RA_CFG_DIR/config/bsnes/bsnes.opt"
          upsert_opt "$BSNES" "bsnes_mode7_scale" "8x"
          upsert_opt "$BSNES" "bsnes_mode7_perspective" "ON"
          upsert_opt "$BSNES" "bsnes_mode7_supersample" "ON"
          upsert_opt "$BSNES" "bsnes_mode7_mosaic" "ON"
          upsert_opt "$BSNES" "bsnes_ips_headered" "ON"

          # Needs Update Slang Shaders first.
          SHADER="$HOME/.config/retroarch/shaders/shaders_slang/xbr/xbr-lv2-multipass.slangp"
          for core in \
            "bsnes" "Snes9x" "FCEUmm" "Nestopia" \
            "Gambatte" "mGBA" "Genesis Plus GX"; do
            CFG="$RA_CFG_DIR/config/$core/$core.cfg"
            upsert_opt "$CFG" "video_shader_enable" "true"
            upsert_opt "$CFG" "video_shader" "$SHADER"
          done
        '';
      };
    }
  ;

  citrix =
    let
      icaOpen = pkgs.writeShellApplication {
        name = "nixly-icaopen";
        runtimeInputs = with pkgs; [
          coreutils
          inotify-tools
          systemd
        ];
        text = ''
          mkdir -p "$HOME/Downloads"
          inotifywait -mq -e moved_to -e close_write --format '%w%f' --include '\.ica$' "$HOME/Downloads" |
            while read -r file; do
              systemd-run --user --quiet -- ${pkgs.citrix-workspace-nixly}/bin/wfica "$file"
            done
        '';
      };
    in
    {
      environment.systemPackages = with pkgs; [
        citrix-workspace-nixly
      ];

      # wfica logs nothing without it.
      systemd.user.services.ctxcwalogd = {
        description = "Citrix Workspace log daemon";
        wantedBy = [ "default.target" ];
        serviceConfig = {
          ExecStart = "${pkgs.citrix-workspace-nixly}/opt/citrix-icaclient/util/ctxcwalogd";
          Restart = "on-failure";
        };
      };

      xdg.mime = {
        enable = true;
        addedAssociations."application/x-ica" = "wfica.desktop";
        defaultApplications."application/x-ica" = "wfica.desktop";
      };

      # Citrix owns wfclient.ini.
      home-manager.users.${nixlyUser} = { lib, ... }: {
        # Stale lockdown keys block wfica.
        home.activation.citrixAllRegionsIni = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          SRC="${pkgs.citrix-workspace-nixly}/opt/citrix-icaclient/config/All_Regions.ini"
          DST="$HOME/.ICAClient/All_Regions.ini"
          if [ -f "$DST" ] && ! cmp -s "$SRC" "$DST"; then
            install -m 600 "$SRC" "$DST"
          fi
        '';

        home.activation.citrixWfclientIni = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          INI="$HOME/.ICAClient/wfclient.ini"
          if [ -f "$INI" ]; then
            # Default fullscreen spans every monitor.
            ${pkgs.gnused}/bin/sed -i \
              's/^UseFullScreen[[:space:]]*=.*/UseFullScreen=False/' "$INI"

            # Read-write home drive, local Super.
            for kv in CDMAllowed=True DriveEnabledA=True 'DrivePathA=$HOME' \
                DriveReadAccessA=0 DriveWriteAccessA=0 SuperMetaToWinKeys=False; do
              key=''${kv%%=*}
              if ${pkgs.gnugrep}/bin/grep -q "^$key[[:space:]]*=" "$INI"; then
                ${pkgs.gnused}/bin/sed -i "s|^$key[[:space:]]*=.*|$kv|" "$INI"
              else
                ${pkgs.gnused}/bin/sed -i "/^\[WFClient\]/a $kv" "$INI"
              fi
            done
          fi
        '';
      };

      # Opens outside the jail.
      systemd.user.services.nixly-icaopen = {
        description = "Open downloaded Citrix launch files";
        partOf = [ "graphical-session.target" ];
        after = [ "graphical-session.target" ];
        wantedBy = [ "graphical-session.target" ];
        serviceConfig = {
          ExecStart = "${icaOpen}/bin/nixly-icaopen";
          Restart = "on-failure";
          RestartSec = 3;
        };
      };
    };

  claudeCode =
    let
      card = pkgs.writeShellApplication {
        name = "claude-thumb-card";
        runtimeInputs = with pkgs; [ libnotify swayimg ];
        text = ''
          action=$(notify-send --app-name=Claude --expire-time=8000 \
            --hint="string:image-path:$1" --action=default=Open --wait \
            "$(basename "$1")")
          if [ "$action" = default ]; then
            exec swayimg "$1"
          fi
        '';
      };

      # Viewer escapes the idle hook.
      hook = pkgs.writeShellApplication {
        name = "claude-thumb";
        runtimeInputs = with pkgs; [ jq util-linux ];
        text = ''
          f=$(jq -r '.tool_input.file_path // empty')
          case "''${f,,}" in
            *.png | *.jpg | *.jpeg | *.webp | *.gif | *.bmp) ;;
            *) exit 0 ;;
          esac
          if [ -f "$f" ]; then
            setsid -f chrt --other 0 ${card}/bin/claude-thumb-card "$f" >/dev/null 2>&1
          fi
        '';
      };

      cli = { pkgs, ... }: {
        home.packages = [ pkgs.claude pkgs.meshy ];
        home.file.".claude/skills/meshy/SKILL.md".source = "${pkgs.meshy}/share/meshy/SKILL.md";
        programs.bash.shellAliases.c = "claude --dangerously-skip-permissions";
      };

      code =
        { lib, ... }:

        {
          home.activation.removeStaleClaudeMd = lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
            if [ -e "$HOME/.claude/CLAUDE.md" ] && [ ! -L "$HOME/.claude/CLAUDE.md" ]; then
              rm -f "$HOME/.claude/CLAUDE.md"
            fi
          '';

          home.file.".claude/CLAUDE.md".text = ''
            1. Think Before Coding

            Don't assume. Don't hide confusion. Surface tradeoffs.

            Before implementing:

            State your assumptions explicitly. If uncertain, ask.
            If multiple interpretations exist, present them - don't pick silently.
            If a simpler approach exists, say so. Push back when warranted.
            If something is unclear, stop. Name what's confusing. Ask.
            2. Simplicity First

            Minimum code that solves the problem. Nothing speculative.

            No features beyond what was asked.
            No abstractions for single-use code.
            No "flexibility" or "configurability" that wasn't requested.
            No error handling for impossible scenarios.
            If you write 200 lines and it could be 50, rewrite it.
            Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

            3. Surgical Changes

            Touch only what you must. Clean up only your own mess.

            When editing existing code:

            Don't "improve" adjacent code, comments, or formatting.
            Don't refactor things that aren't broken.
            Match existing style, even if you'd do it differently.
            If you notice unrelated dead code, mention it - don't delete it.
            When your changes create orphans:

            Remove imports/variables/functions that YOUR changes made unused.
            Don't remove pre-existing dead code unless asked.
            The test: Every changed line should trace directly to the user's request.

            4. Goal-Driven Execution

            Define success criteria. Loop until verified.

            Transform tasks into verifiable goals:

            "Add validation" → "Write tests for invalid inputs, then make them pass"
            "Fix the bug" → "Write a test that reproduces it, then make it pass"
            "Refactor X" → "Ensure tests pass before and after"
            For multi-step tasks, state a brief plan:

            1. [Step] → verify: [check]
            2. [Step] → verify: [check]
            3. [Step] → verify: [check]
            Strong success criteria let you loop independently. Weak criteria ("make it work") require constant clarification.

            5. Never commit or push changes.

            6. File and Folder Organization

            One thing per file. Short, descriptive names. Related files grouped in short, descriptive folders.

            A file is named after the one thing it contains. No plural dumping grounds.
            No file named utils, helpers, common, misc, core, shared, lib, or stuff.
            No file over ~300 lines. If it grew past that, it holds more than one thing.
            Folder depth stays shallow - three levels from the repo root is the normal maximum.
            Folders group by feature, not by file type. Not controllers/models/views.
            A folder with one file is not a folder. A folder with twenty files is two folders.
            Name files after what they are, not when they arrived: no new, old, tmp, backup, v2, final.

            7. Comments

            Max one comment per thing. One sentence, max 5 descriptive words.
            This applies everywhere, including existing files: when touching code with longer comments, shorten them to fit this rule. This overrides "match existing style" for comments.

            8. Database Work

            All database work is done cleanly and professionally.

            No database may have artificial limitations or bottlenecks.
            Index what is queried. No N+1 queries, no unbounded scans.
            Schema changes go through proper migrations.

            9. Nix Projects

            Every nix project ships a flake:

            "nix develop" provides everything the project needs.
            "nix run" always runs the project.
            If servers are involved, they start automatically first — then the program or website pops up on its own.

            10. Performance

            Only highly efficient code, optimized for best possible performance.

            Never take the shortest path to a result — take the optimized path, with clean and efficient code.
            Prefer the least code that achieves it.

            11. Look and Feel

            Everything user-facing must look modern and professional, with tasteful eye-candy.

            12. Hash Updates (nixlypkgs)

            When asked to refresh a derivation hash, do it lightning-fast: fetch new hash, update rev/hash, done. No analysis, no questions, no extra reading.

            13. No AI Fingerprints

            Code must read like one experienced human wrote it.

            Never: banner comments, emoji, decorative separators, section headers inside code.
            Never: comments restating the line below, docstrings on obvious functions, "Note that", "This ensures that".
            Never: leftover placeholders, "rest of code unchanged", commented-out old code beside new code.
            Never: symmetric boilerplate applied everywhere - try/catch around every call, {ok, error} on every return, null checks for values that cannot be null.
            Never: names like data, result, temp, info, helper, manager, handler, utils, processX, doX, enhanced, improved, v2.
            Never: a summary paragraph at the top of a file restating what the file does.
            Never: duplicated near-identical blocks that should be a loop or a table.
            If a reviewer could name the tool that wrote it, rewrite it.

            14. Control Flow

            Flat beats nested. Always.

            No nested if statements. Invert the condition and return early.
            Max two levels of indentation inside a function body. Three means a function is missing.
            No else after return, break, or continue.
            No if/else chain longer than three arms - use a table, map, or switch on an enum.
            No boolean parameter that selects behaviour - write two functions.
            Handle the error case first; the happy path runs unindented to the end.
            No nested loops that could be hoisted, flattened, or indexed.

            15. Function and Data Shape

            One function, one job, one level of abstraction.

            A function fits on one screen. If it does not, it is doing two things.
            Three arguments or fewer. More means a struct is missing.
            One way out: no out-parameters mixed with return values.
            No stringly-typed state - enums or tagged unions.
            No magic numbers or magic strings - named constants.
            Validate at the boundary, trust inside it. No re-checking downstream.
            Plain data plus functions beats a class that exists to hold one value.

            16. Optimized Means Measured

            "Optimized" is a claim, and claims need evidence.

            Name the hot path before optimizing it.
            Allocate outside the loop, never inside. Compute invariants once.
            Contiguous arrays over pointer chasing; indices over pointers when data can move.
            No hidden work: no accidental copy, no formatting in a hot loop, no syscall per iteration.
            Right algorithm first, micro-optimization after.
            If the faster version is uglier with no measured win, keep the clear one.

            17. Definition of Done

            Done means a top-tier engineer finds nothing to change.

            Builds clean with all warnings enabled. Zero warnings, zero suppressions.
            No dead code, unused arguments, or unused imports left by your change.
            No TODO, FIXME, or stub that you introduced.
            Every line justifies itself. Delete what you cannot defend.
            Re-read the whole diff as a reviewer before reporting done. If you would comment on it, fix it first.
            Taking longer is fine. Shipping work that needs a second pass is not.

            18. Project Structure

            An experienced developer opens the repo and knows where everything is in thirty seconds.

            The root holds only what must be there: README, flake.nix, and the top-level source folders. Nothing else.
            No stray scripts, notes, logs, backups, or scratch files anywhere in the tree. Those live outside the repo.
            Every folder name says what lives in it. If you need a comment to explain the layout, the layout is wrong.
            Structure mirrors the domain, so the folder tree reads as the feature list.
            One obvious place for each kind of thing, and only one. No parallel half-migrated layouts.
            Entry points are obvious and few: one way to build, one way to run, one way to test.
            Generated and vendored output never mixes with source, and is gitignored.
            README is short: what it is, how to run it, how the tree is laid out. Nothing that will rot.
            Before finishing a task, look at the tree you leave behind. If a new developer would ask "why is this here?", move it or delete it.

            19. Gitignore

            Every project ships a .gitignore at the repo root. Only source belongs in git.

            Create it in the first commit of a new project. If a project lacks one, add it before anything else.
            Ignore all agent and LLM artifacts: .claude/, .cursor/, .aider*, .continue/, .windsurf/, .codeium/, .github/copilot*, *.agent.md, chat and session logs, plan/summary/analysis notes, and any scratch file an assistant produced.
            Ignore build output, generated code, and vendored dependencies: result, result-*, build/, dist/, target/, node_modules/, .venv/, __pycache__/, *.o, *.so.
            Ignore secrets and local config: .env, .env.*, *.key, *.pem, *.local, local settings files.
            Ignore editor and OS junk: .idea/, .vscode/, *.swp, .DS_Store, Thumbs.db.
            Ignore caches and logs: .cache/, *.log, coverage/, .direnv/.
            Keep it curated and short: entries for what this project actually produces, not a copied 300-line template. No blanket wildcards that hide real source.
            Never commit a file the .gitignore is meant to catch, and never force-add one.
            A tracked file that should be ignored is a bug: say so, and fix the ignore rule.

            20. 3D Assets

            Meshes, props, characters and animations come from the `meshy` CLI (skill: meshy), never hand-built geometry or placeholder shapes when a real asset is wanted.
            Load the meshy skill before touching 3D assets in a Bevy project.
          '';
        }
      ;

      caveman =
        { config, pkgs, lib, ... }:

        let
          caveman-src = pkgs.fetchFromGitHub {
            owner = "JuliusBrussee";
            repo = "caveman";
            rev = "600e8efcd6aca4006051ca2a889aa8100a9b3967";
            hash = "sha256-gDPgQx1TIhGrJ2EVvEoDY+4MXdlI79zdcx6pL5nMEG4=";
          };
        in
        {
          home.packages = [ pkgs.nodejs ];

          home.file = {
            # Node resolves symlinks to store.
            ".claude/hooks/caveman-config.js".source = "${caveman-src}/hooks/caveman-config.js";
            ".claude/hooks/caveman-activate.js".source = "${caveman-src}/hooks/caveman-activate.js";
            ".claude/hooks/caveman-mode-tracker.js".source = "${caveman-src}/hooks/caveman-mode-tracker.js";
            ".claude/hooks/caveman-statusline.sh" = {
              source = "${caveman-src}/hooks/caveman-statusline.sh";
              executable = true;
            };

            # Slash commands
            ".claude/commands/caveman.toml".source = "${caveman-src}/commands/caveman.toml";
            ".claude/commands/caveman-commit.toml".source = "${caveman-src}/commands/caveman-commit.toml";
            ".claude/commands/caveman-review.toml".source = "${caveman-src}/commands/caveman-review.toml";
          };

          # Merged into mutable settings.json.
          home.activation.setupCavemanHooks = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
                SETTINGS="$HOME/.claude/settings.json"
                mkdir -p "$HOME/.claude"

                if [ ! -f "$SETTINGS" ]; then
                  echo '{}' > "$SETTINGS"
                fi

                ${pkgs.nodejs}/bin/node - "$SETTINGS" << 'NODEOF'
            const fs = require("fs");
            const settingsPath = process.argv[2];

            let settings = {};
            try { settings = JSON.parse(fs.readFileSync(settingsPath, "utf8")); } catch {}

            if (!settings.hooks) settings.hooks = {};
            if (!Array.isArray(settings.hooks.SessionStart)) settings.hooks.SessionStart = [];
            if (!Array.isArray(settings.hooks.UserPromptSubmit)) settings.hooks.UserPromptSubmit = [];

            // Drop old caveman hooks.
            const notCaveman = (e) =>
              !(e.hooks && e.hooks.some((h) => h.command && h.command.includes("caveman")));

            settings.hooks.SessionStart = settings.hooks.SessionStart.filter(notCaveman);
            settings.hooks.UserPromptSubmit = settings.hooks.UserPromptSubmit.filter(notCaveman);

            settings.hooks.SessionStart.push({
              hooks: [
                {
                  type: "command",
                  command: "node $HOME/.claude/hooks/caveman-activate.js",
                  timeout: 5000,
                },
              ],
            });

            settings.hooks.UserPromptSubmit.push({
              hooks: [
                {
                  type: "command",
                  command: "node $HOME/.claude/hooks/caveman-mode-tracker.js",
                  timeout: 5000,
                },
              ],
            });

            fs.writeFileSync(settingsPath, JSON.stringify(settings, null, 2) + "\n");
            NODEOF
          '';
        }
      ;
    in
    {
      # Image reads become notification cards.
      environment.etc."claude-code/managed-settings.json".text = builtins.toJSON {
        hooks.PostToolUse = [
          {
            matcher = "Read";
            hooks = [
              {
                type = "command";
                command = "${hook}/bin/claude-thumb";
              }
            ];
          }
        ];
      };

      home-manager.sharedModules = [ cli code caveman ];
    };

  blenderSetup =
    { config, pkgs, lib, ... }:

    let
      cfg = config.nixly.blender;

      # Official LTS has every kernel.
      blenderPkg = pkgs.Blender_bin_lts;

      blenderBin = lib.getExe blenderPkg;

      # Best backend per vendor.
      cyclesDevice = {
        nvidia = "OPTIX";
        amd = "HIP";
        intel = "ONEAPI";
      }.${cfg.variant};

      acceptedDeviceTypes = {
        nvidia = [ "OPTIX" "CUDA" ];
        amd = [ "HIP" ];
        intel = [ "ONEAPI" ];
      }.${cfg.variant};

      # Bundled with Blender under legacy module IDs.
      bundledAddons = [ "node_wrangler" "rigify" ];

      # Typo "objectes" is upstream's.
      extensionAddons = [
        "looptools"
        "f2"
        "auto_mirror"
        "copy_attributes_menu"
        "bool_tool"
        "extra_mesh_objects"
        "extra_curve_objectes"
      ];

      # Bump URL and hash together.
      fetchExt = url: sha256: pkgs.fetchurl { inherit url sha256; };
      extZips = {
        looptools = fetchExt
          "https://extensions.blender.org/download/sha256:ff1ca3b3fff73094379da8b1fa2c1acbc9d88d26b7dfc73bb9de5941a6b50108/add-on-looptools-v4.7.7.zip"
          "ff1ca3b3fff73094379da8b1fa2c1acbc9d88d26b7dfc73bb9de5941a6b50108";
        f2 = fetchExt
          "https://extensions.blender.org/download/sha256:dc8f19637a61c332b3eb937a6b86e2363511cbb29a9a22ea8571fe7d924ab05c/add-on-f2-v1.8.5.zip"
          "dc8f19637a61c332b3eb937a6b86e2363511cbb29a9a22ea8571fe7d924ab05c";
        auto_mirror = fetchExt
          "https://extensions.blender.org/download/sha256:68c7785f641c91905b07b8122af6a0147834e9a7b77285966253b1f770f30cc7/add-on-auto-mirror-v2.5.4.zip"
          "68c7785f641c91905b07b8122af6a0147834e9a7b77285966253b1f770f30cc7";
        copy_attributes_menu = fetchExt
          "https://extensions.blender.org/download/sha256:990bac36be4c6a39c4506c84a689c5ec45e1a4b43995542cd0b058663f190478/add-on-copy-attributes-menu-v0.6.3.zip"
          "990bac36be4c6a39c4506c84a689c5ec45e1a4b43995542cd0b058663f190478";
        bool_tool = fetchExt
          "https://extensions.blender.org/download/sha256:9d9c73f2f49af05e3a3cfe78daa43676b1005fcbb591dc054d9d04c370f0d85d/add-on-bool-tool-v2.0.0.zip"
          "9d9c73f2f49af05e3a3cfe78daa43676b1005fcbb591dc054d9d04c370f0d85d";
        extra_mesh_objects = fetchExt
          "https://extensions.blender.org/download/sha256:c85ce4bb2820d5af26b4dad66bf1a0fdeb4bfeffc668c5e4f098f1e416ed434b/add-on-extra-mesh-objects-v0.4.1.zip"
          "c85ce4bb2820d5af26b4dad66bf1a0fdeb4bfeffc668c5e4f098f1e416ed434b";
        extra_curve_objectes = fetchExt
          "https://extensions.blender.org/download/sha256:4ca91ce5563d094694b2c7f1fc9acece8b5ba8f5dd017a49f080e9cfa5553909/add-on-extra-curve-objectes-v0.2.0.zip"
          "4ca91ce5563d094694b2c7f1fc9acece8b5ba8f5dd017a49f080e9cfa5553909";
      };
      extZipPaths = lib.mapAttrsToList (_: zip: "${zip}") extZips;

      # GitHub source as legacy addon.
      blenderkitSrc = pkgs.fetchFromGitHub {
        owner = "BlenderKit";
        repo = "BlenderKit";
        rev = "5d252bee50bef7e409caad047432c028c28e10fa";
        hash = "sha256-QIwMDN4B3XDoi+OMnuURpRv/1bs7bzfBRbsdRBFNe3Y=";
      };

      setupPy = pkgs.writeText "blender-setup.py" ''
        import bpy, addon_utils

        bundled         = ${builtins.toJSON bundledAddons}
        extension_ids   = ${builtins.toJSON extensionAddons}
        extension_zips  = ${builtins.toJSON extZipPaths}
        accepted_devs   = ${builtins.toJSON acceptedDeviceTypes}
        cycles_dev_type = "${cyclesDevice}"

        def safe(label, fn):
            try: fn()
            except Exception as e: print(f"[setup] {label}: {e}")

        # Install pinned extensions from local zips.
        for z in extension_zips:
            safe(f"install {z}", lambda z=z: bpy.ops.extensions.package_install_files(
                filepath=z, repo="user_default", enable_on_install=True))

        # Enable bundled addons and BlenderKit.
        for a in bundled + ["blenderkit"]:
            safe(f"enable {a}", lambda a=a:
                addon_utils.enable(a, default_set=True, persistent=True))

        # enable_on_install misses some.
        for ext in extension_ids:
            mod = f"bl_ext.user_default.{ext}"
            safe(f"enable ext {ext}", lambda mod=mod:
                bpy.ops.preferences.addon_enable(module=mod))

        # Cycles compute device.
        def setup_cycles():
            cprefs = bpy.context.preferences.addons["cycles"].preferences
            cprefs.compute_device_type = cycles_dev_type
            cprefs.refresh_devices()
            for d in cprefs.devices:
                d.use = d.type in accepted_devs
        safe("cycles devices", setup_cycles)

        # System and performance
        sysprefs = bpy.context.preferences.system
        safe("gpu_backend",       lambda: setattr(sysprefs, "gpu_backend", "VULKAN"))
        safe("memory_cache",      lambda: setattr(sysprefs, "memory_cache_limit", 8192))
        safe("gpu_subdivision",   lambda: setattr(sysprefs, "use_gpu_subdivision", True))

        # Edit and undo
        edit = bpy.context.preferences.edit
        edit.undo_steps = 256
        edit.undo_memory_limit = 1024

        # Input
        inp = bpy.context.preferences.inputs
        inp.view_rotate_method            = "TURNTABLE"
        inp.use_zoom_to_mouse             = True
        inp.use_rotate_around_active      = True   # Orbit Around Selection
        inp.use_auto_depth                = True   # Auto Depth (under Orbit Around Selection)
        inp.use_mouse_emulate_3_button    = True
        inp.mouse_emulate_3_button_modifier = "ALT"
        safe("tablet_api", lambda: setattr(inp, "tablet_api", "AUTOMATIC"))

        # View and UI
        bpy.context.preferences.view.ui_scale = 1.5

        # Save
        bpy.ops.wm.save_userpref()
        print("[setup] complete")
      '';
    in
    {
      options.nixly.blender = {
        variant = lib.mkOption {
          type = lib.types.enum [ "nvidia" "amd" "intel" ];
          default = "nvidia";
          description = "Blender GPU variant — picks Cycles backend + auto-enabled compute device";
        };
      };

      config = {
        home.packages = [ blenderPkg ];

        home.file.".config/blender/5.2/scripts/addons/blenderkit".source = blenderkitSrc;

        # Delete the flag to rerun.
        home.activation.blenderSetup = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          FLAG="$HOME/.config/blender/.nix_setup_v2"
          if [ ! -f "$FLAG" ] && [ -x "${blenderBin}" ]; then
            echo "[blender] bootstrapping addons + prefs (one-time)..."
            mkdir -p "$HOME/.config/blender"
            if "${blenderBin}" --background --python "${setupPy}"; then
              touch "$FLAG"
              echo "[blender] setup complete"
            else
              echo "[blender] setup failed; will retry on next HM rebuild"
            fi
          fi
        '';
      };
    }
  ;

  blender = {
    home-manager.sharedModules = [ blenderSetup ];
  };
in
{
  imports = [ emulation claudeCode ] ++ lib.optionals x86 [ unreal citrix blender ];

  assertions = [{
    assertion = config.nixlyos.mode == "desktop";
    message = "Desktop-modulen hører til profiler med plattform desktop.";
  }];

  home-manager.sharedModules = [ tools speakers ] ++ lib.optional x86 terrain;
}
$nix$),
('htpc', 'HTPC', 'Stuemodus: én app om gangen, media, TV-lyd og nattlig oppdatering.', false, 10, $nix${ config, lib, pkgs, nixlyUser, ... }:

let
  # Intel iGPU PCI slot.
  igpuSlot = "0000:00:02.0";

  # Installed by media, kept warm.
  retroarchFull = pkgs.retroarch.withCores (cores: with cores; [
    nestopia
    snes9x
    bsnes
    genesis-plus-gx
    mupen64plus
    beetle-psx-hw
    pcsx-rearmed
    mgba
    gambatte
    beetle-saturn
    flycast
    melonds
    mame
    stella
    ppsspp
    fbneo
    # ROM share has these folders.
    pcsx2
    dolphin
  ]);

  # No greeter, ever.
  login = {
    services.displayManager.autoLogin = {
      enable = true;
      user = nixlyUser;
    };
    services.displayManager.sddm.autoLogin.relogin = true;
  };

  # One app at a time.
  session =
    let
      # Widest connected output becomes primary.
      setRandrPrimary = pkgs.writeShellScript "nixly-xrandr-primary" ''
        for _ in $(seq 10); do
          out=$(${pkgs.xrandr}/bin/xrandr 2>/dev/null \
            | sed -n 's/^\([^ ]*\) connected.* \([0-9]\+\)x[0-9]\++.*/\2 \1/p' \
            | sort -rn | head -1 | cut -d' ' -f2)
          if [ -n "$out" ] && ${pkgs.xrandr}/bin/xrandr --output "$out" --primary 2>/dev/null; then
            exit 0
          fi
          sleep 1
        done
      '';

      # Supervisor: restarts the app on exit.
      htpcLoop = pkgs.writeShellScript "htpc-loop" ''
        app="$1"
        while :; do
          case "$app" in
            steam)
              ${setRandrPrimary} &
              steam -tenfoot
              ;;
            geforcenow) nixly-gfn ;;
            nixlymedia) nixlymedia ;;
            *)          retroarch ;;
          esac
          # A boot-looping app must not spin.
          sleep 0.3
        done
      '';

      htpcSwitch = pkgs.writeShellScriptBin "htpc-switch" ''
        app="$1"
        uid=$(${pkgs.coreutils}/bin/id -u)
        cg=/sys/fs/cgroup/user.slice/user-$uid.slice/user@$uid.service

        for kill in "$cg"/app.slice/htpc-app-*.scope/cgroup.kill \
                    "$cg"/app.slice/app-flatpak-com.nvidia.geforcenow-*.scope/cgroup.kill; do
          [ -e "$kill" ] && echo 1 > "$kill"
        done

        # GFN runs outside our scope.
        if grep -q '^populated 1' "$cg/gfn.slice/cgroup.events" 2>/dev/null; then
          echo 1 > "$cg/gfn.slice/cgroup.kill"
          ${pkgs.systemd}/bin/systemctl stop --no-block gfn-focus.service 2>/dev/null || true
        fi

        # RP1 for media, full for games.
        htpc-gpu-clock "$app" 2>/dev/null || true

        exec ${pkgs.systemd}/bin/systemd-run --user --scope --quiet --collect \
          --slice=app.slice --unit="htpc-app-$app-$$" -- ${htpcLoop} "$app"
      '';
    in
    {
      environment.systemPackages = [ htpcSwitch ];
    }
  ;

  # RetroArch, mpv, unmuted sinks.
  media =
    let
      # Guide button belongs to nixlytile.
      joypadAutoconfigNoGuide =
        pkgs.runCommand "retroarch-joypad-autoconfig-noguide" { } ''
          cp -r ${pkgs.retroarch-joypad-autoconfig} $out
          chmod -R u+w $out
          find $out -name '*.cfg' \
            -exec sed -i '/^input_menu_toggle_btn/d' {} +
        '';
    in
    {

      environment.systemPackages =
        (with pkgs; [
          nixlymedia
          retroarchFull
          retroarch-assets
          retroarch-joypad-autoconfig
          libretro-shaders-slang
        ]);

      home-manager.users.${nixlyUser} = { pkgs, ... }:
        let
          # wpctl's MUTED tag is unlocalized.
          unmuteMuted = pkgs.writeShellScript "htpc-audio-unmute-muted" ''
            set -u
            WPCTL=${pkgs.wireplumber}/bin/wpctl
            "$WPCTL" status | ${pkgs.gawk}/bin/awk '
              /Sinks:/   {on=1} /Sources:/ {on=1} /Streams:/ {on=1}
              /Filters:/ {on=0} /Video/    {on=0} /Settings/ {on=0}
              on && match($0, /[0-9]+\./) { print substr($0, RSTART, RLENGTH-1) }
            ' | sort -u | while read -r id; do
              "$WPCTL" get-volume "$id" 2>/dev/null \
                | ${pkgs.gnugrep}/bin/grep -q MUTED && "$WPCTL" set-mute "$id" 0 || true
            done
          '';

          # Every sink unmuted at 80 %.
          setAllSinks = pkgs.writeShellScript "htpc-audio-set-all-sinks-80" ''
            set -u
            WPCTL=${pkgs.wireplumber}/bin/wpctl
            "$WPCTL" status | ${pkgs.gawk}/bin/awk '
              /Sinks:/ {insinks=1; next}
              /Sources:/ {insinks=0}
              insinks && match($0, /[0-9]+\./) { print substr($0, RSTART, RLENGTH-1) }
            ' | while read -r id; do
              "$WPCTL" set-mute "$id" 0 || true
              "$WPCTL" set-volume "$id" 0.8 || true
            done
          '';
        in
        {

          # 4K Vulkan on Arc.
          xdg.configFile."retroarch/retroarch.cfg".text = ''
            video_driver = "vulkan"
            video_fullscreen = "true"
            video_windowed_fullscreen = "false"
            video_fullscreen_x = "3840"
            video_fullscreen_y = "2160"
            video_vsync = "true"
            video_adaptive_vsync = "true"
            video_hard_sync = "false"
            # Three images pinned 10 fps.
            video_max_swapchain_images = "4"
            # Adds a frame on Vulkan.
            video_threaded = "false"
            video_frame_delay = "0"
            video_frame_delay_auto = "true"
            video_gpu_screenshot = "true"
            video_shared_context = "true"

            video_aspect_ratio_auto = "true"
            aspect_ratio_index = "22"
            video_scale_integer = "false"
            video_smooth = "true"
            video_ctx_scaling = "true"
            video_force_aspect = "true"

            # Per-core presets set shaders.
            video_shader_enable = "true"
            video_shader_dir = "${pkgs.libretro-shaders-slang}/share/libretro/shaders/shaders_slang"

            # Volume in dB, 0 = unity.
            audio_driver = "pipewire"
            audio_enable = "true"
            audio_sync = "true"
            audio_volume = "0.0"
            audio_mute_enable = "false"
            audio_latency = "32"

            # XMB, neoactive, electric blue.
            menu_driver = "xmb"
            xmb_theme = "4"
            xmb_menu_color_theme = "4"
            menu_show_load_content = "true"
            menu_show_quit_retroarch = "true"
            menu_show_restart_retroarch = "true"
            menu_show_online_updater = "true"
            menu_show_core_updater = "true"
            quit_press_twice = "false"
            menu_enable_widgets = "true"
            menu_widget_scale_auto = "true"

            input_max_users = "4"
            input_autodetect_enable = "true"
            input_joypad_driver = "sdl2"
            input_menu_toggle_gamepad_combo = "2"

            savestate_auto_save = "true"
            savestate_auto_load = "true"
            savestate_thumbnail_enable = "true"
            # Switching kills without flushing.
            autosave_interval = "10"

            pause_nonactive = "false"
            fps_show = "false"

            assets_directory = "${pkgs.retroarch-assets}/share/retroarch/assets"
            joypad_autoconfig_dir = "${joypadAutoconfigNoGuide}/share/libretro/autoconfig"

            # Written by apps/rom-playlists.
            playlist_directory = "~/.config/retroarch/playlists"
            content_show_playlists = "true"
          '';

          # No judder on the 60 Hz panel.
          programs.mpv = {
            enable = true;

            # Overrides the desktop mpv config.
            config = lib.mkForce {
              idle = "no";
              terminal = "no";
              force-window = "immediate";
              osc = "yes";
              pause = "no";
              hr-seek = "yes";
              save-position-on-quit = "no";
              msg-level = "all=v";
              log-file = "/tmp/mpv.log";
              ao = "pipewire";

              vo = "gpu-next";
              gpu-api = "vulkan";
              gpu-context = "auto";
              # Pool contention stuttered motion.
              hwdec = "vaapi-copy";
              vd-lavc-dr = "no";
              hwdec-codecs = "all";
              vulkan-swap-mode = "fifo";
              swapchain-depth = 3;
              gpu-shader-cache-dir = "~/.cache/mpv/shaders";

              fullscreen = "yes";
              keep-open = "yes";
              cursor-autohide = 500;

              # Blends 24p into 60 Hz.
              video-sync = "display-resample";
              interpolation = "yes";
              tscale = "oversample";
              framedrop = "no";
              video-latency-hacks = "no";
              hr-seek-framedrop = "no";

              scale = "ewa_lanczossharp";
              cscale = "ewa_lanczossoft";
              dscale = "mitchell";
              correct-downscaling = "yes";
              linear-downscaling = "yes";
              sigmoid-upscaling = "yes";
              dither-depth = "auto";
              deband = "yes";
              deband-iterations = 1;
              deband-threshold = 35;
              deband-range = 16;
              deband-grain = 4;

              target-colorspace-hint = "yes";
              target-peak = "auto";
              hdr-compute-peak = "no";
              tone-mapping = "bt.2446a";
              gamut-mapping-mode = "perceptual";

              # PCM, never an exclusive sink.
              audio-channels = "auto";
              audio-exclusive = "no";
              volume = "100";
              volume-max = "100";

              # Absorbs jitter at 4K bitrates.
              cache = "yes";
              cache-secs = 180;
              cache-pause = "yes";
              cache-pause-wait = 1;
              cache-pause-initial = "no";
              cache-on-disk = "no";
              demuxer-max-bytes = "1GiB";
              demuxer-max-back-bytes = "128MiB";
              demuxer-readahead-secs = 60;
              demuxer-seekable-cache = "yes";
              demuxer-hysteresis-secs = 10;
              stream-buffer-size = "64MiB";
              network-timeout = 60;
              prefetch-playlist = "yes";

              sub-auto = "fuzzy";
              slang = "no,nob,en,eng";
              alang = "no,nob,en,eng";

              sub-font-size = 30;
              sub-border-size = 2;
              sub-shadow-offset = 0;

              screenshot-format = "png";
              screenshot-directory = "~/Pictures/mpv";
            };
          };

          # Every sink at 80 %.
          systemd.user.services.htpc-audio-unmute = {
            Unit = {
              Description = "HTPC: unmute all sinks and set volume to 80%";
              After = [ "graphical-session.target" "wireplumber.service" ];
              PartOf = [ "graphical-session.target" ];
            };
            Install.WantedBy = [ "graphical-session.target" ];
            Service = {
              Type = "oneshot";
              ExecStart = pkgs.writeShellScript "htpc-audio-unmute" ''
                set -u
                WPCTL=${pkgs.wireplumber}/bin/wpctl
                for _ in 1 2 3 4 5; do
                  "$WPCTL" get-volume @DEFAULT_AUDIO_SINK@ >/dev/null 2>&1 && break
                  sleep 1
                done
                ${setAllSinks}
                ${unmuteMuted}
              '';
            };
          };

          # nixlymedia mutes its own stream.
          systemd.user.services.htpc-audio-watch = {
            Unit = {
              Description = "HTPC: keep sinks/sources/streams unmuted";
              After = [ "htpc-audio-unmute.service" "pipewire.service" ];
              PartOf = [ "graphical-session.target" ];
            };
            Install.WantedBy = [ "graphical-session.target" ];
            Service = {
              Type = "simple";
              # Exits cleanly when pulse restarts.
              Restart = "always";
              RestartSec = 2;
              ExecStart = pkgs.writeShellScript "htpc-audio-watch" ''
                set -u
                ${pkgs.pulseaudio}/bin/pactl subscribe 2>/dev/null | while IFS= read -r line; do
                  case "$line" in
                    "Event 'new' on sink "*)
                      sleep 0.3
                      ${setAllSinks}
                      ;;
                    "Event 'new' on sink-input "*|"Event 'change' on sink-input "*|"Event 'new' on source "*)
                      sleep 0.2
                      ${unmuteMuted}
                      ;;
                  esac
                done
              '';
            };
          };
        };
    }
  ;

  # Stereo to the TV.
  audio =
    {

      services.pipewire.wireplumber.extraConfig."55-htpc-hdmi-priority" = {
        "device.profile.priority.rules" = [
          {
            matches = [
              { "device.name" = "~alsa_card.*"; }
            ];
            actions = {
              update-props = {
                priorities = [ "output:hdmi-stereo" ];
              };
            };
          }
        ];
        "monitor.alsa.rules" = [
          {
            matches = [
              { "device.name" = "~alsa_card.*"; }
            ];
            actions = {
              update-props = {
                "api.acp.auto-port" = true;
              };
            };
          }
          {
            matches = [
              { "node.name" = "~alsa_output.*hdmi.*"; }
            ];
            actions = {
              update-props = {
                "priority.session" = 3000;
                "priority.driver" = 3000;
              };
            };
          }
        ];
      };

      # Saved surround state beats priorities.
      systemd.user.services.htpc-wp-state-reset = {
        description = "Remove saved surround profiles from WirePlumber state";
        before = [ "wireplumber.service" ];
        partOf = [ "wireplumber.service" ];
        wantedBy = [ "wireplumber.service" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = pkgs.writeShellScript "htpc-wp-state-reset" ''
            set -u
            D="''${XDG_STATE_HOME:-$HOME/.local/state}/wireplumber"
            [ -d "$D" ] || exit 0
            ${pkgs.gnused}/bin/sed -i '/hdmi-surround/d' \
              "$D/default-profile" "$D/default-routes" 2>/dev/null || true
          '';
        };
      };
    };

  # Modeset enables the codec.
  hdmiAudio =
    {
      # Idle mute.
      boot.extraModprobeConfig = ''
        options snd_hda_codec_intelhdmi enable_silent_stream=N
      '';

      systemd.services.htpc-hdmi-audio = {
        description = "Force a modeset so i915 enables the HDMI/DP audio codec";
        wantedBy = [ "multi-user.target" ];
        before = [ "display-manager.service" ];
        after = [ "sound.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = pkgs.writeShellScript "htpc-hdmi-audio" ''
            set -u
            GREP=${pkgs.gnugrep}/bin/grep

            eld_ok() {
              $GREP -lE 'eld_valid[[:space:]]+1' /proc/asound/card*/eld* 2>/dev/null \
                | $GREP -q .
            }

            connected() {
              for s in /sys/class/drm/card*-*/status; do
                [ "$(cat "$s" 2>/dev/null)" = connected ] || continue
                dirname "$s"
                return 0
              done
              return 1
            }

            # Connector and ELD files first.
            have_eld_files() {
              for f in /proc/asound/card*/eld*; do
                [ -e "$f" ] && return 0
              done
              return 1
            }

            for _ in $(seq 30); do
              connected >/dev/null && have_eld_files && break
              sleep 1
            done

            conn=$(connected) || exit 0

            for _ in $(seq 3); do
              eld_ok && exit 0
              echo off    > "$conn/status"
              sleep 2
              echo detect > "$conn/status"
              sleep 3
            done

            eld_ok || echo "htpc-hdmi-audio: ELD still invalid on $conn, TV has no audio" >&2
            exit 0
          '';
        };
      };
    };

  # Shared BIOS dumps from NFS.
  biosSync =
    {

      home-manager.users.${nixlyUser} = {
        systemd.user.services.htpc-bios-sync = {
          Unit.Description = "HTPC: sync BIOS files from NFS to RetroArch";
          Service = {
            Type = "oneshot";
            ExecStart = pkgs.writeShellScript "htpc-bios-sync" ''
              set -u
              src=/mnt/nfs/Bigdisk1/Emulator/BIOS
              dst="$HOME/.config/retroarch/system"
              # Keep earlier syncs when down.
              [ -d "$src" ] || exit 0
              mkdir -p "$dst"
              # Skip the original bundles.
              ${pkgs.rsync}/bin/rsync -rt --exclude 'README*' --exclude '_*' \
                "$src/" "$dst/"
            '';
          };
        };

        systemd.user.timers.htpc-bios-sync = {
          Unit.Description = "HTPC: periodic BIOS re-sync";
          Install.WantedBy = [ "timers.target" ];
          Timer = {
            OnStartupSec = "30s";
            OnUnitActiveSec = "30min";
          };
        };
      };
    };

  # 4K picture per core.
  retroarch4k =
    let
      xbr = "${pkgs.libretro-shaders-slang}/share/libretro/shaders/shaders_slang/edge-smoothing/xbr/xbr-lv2.slangp";
      preset2d = core: {
        "retroarch/config/${core}/${core}.slangp".text = ''
          #reference "${xbr}"
        '';
      };
    in
    {

      home-manager.users.${nixlyUser} = {
        xdg.configFile = lib.mkMerge [
          # Library names the cores report.
          (preset2d "Nestopia")
          (preset2d "Snes9x")
          (preset2d "mGBA")
          (preset2d "Gambatte")
          {
            # PS2 stretches to the panel.
            "retroarch/config/LRPS2/LRPS2.cfg".text = ''
              aspect_ratio_index = "24"
            '';
          }
          {
            "retroarch/retroarch-core-options.cfg".text = ''
              # N64 at 8x internal.
              mupen64plus-rdp-plugin = "parallel"
              mupen64plus-parallel-rdp-upscaling = "8x"

              # PS2 native, upscaling stalls readback.
              pcsx2_upscale_multiplier = "1x Native (PS2)"
              pcsx2_widescreen_hint = "enabled"

              # GC/Wii at 6x EFB.
              dolphin_efb_scale = "6x Native (3840x3168) for 4K"
            '';
          }
        ];
      };
    }
  ;

  # Arc pinned at RP1.
  gpuClocks =
    let
    in
    {
      systemd.services.htpc-gpu-clocks = {
        description = "Pin Intel Arc GPU clocks at RP1 (VRM noise on TV/eARC above)";
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = pkgs.writeShellScript "htpc-gpu-clocks" ''
            set -u
            # Waits for i915's knobs.
            pinned=0
            for _ in $(seq 60); do
              for card in /sys/class/drm/card*; do
                [ -e "$card/gt_RP0_freq_mhz" ] || continue
                rp1=$(cat "$card/gt_RP1_freq_mhz")
                cap=$rp1
                # iGPU has no card VRM.
                [ "$(basename "$(readlink -f "$card/device")")" = ${igpuSlot} ] \
                  && cap=$(cat "$card/gt_RP0_freq_mhz")
                # Max never drops below min.
                echo "$rp1" > "$card/gt_min_freq_mhz"   || true
                echo "$cap" > "$card/gt_max_freq_mhz"   || true
                echo "$cap" > "$card/gt_boost_freq_mhz" || true
                pinned=1
              done
              [ "$pinned" = 1 ] && break
              sleep 1
            done
            # Display devices stay awake.
            for dev in /sys/bus/pci/devices/*; do
              case "$(cat "$dev/class")" in
                0x03*) echo on > "$dev/power/control" || true ;;
              esac
            done
          '';
        };
      };
    }
  ;

  # Full range for games.
  gpuClock =
    let

      gpuClock = pkgs.writeShellScriptBin "htpc-gpu-clock" ''
        set -u
        case "''${1:-}" in
          steam|retroarch) mode=high ;;
          *)               mode=low  ;;
        esac

        for card in /sys/class/drm/card*; do
          [ -e "$card/gt_max_freq_mhz" ] || continue
          rp0=$(cat "$card/gt_RP0_freq_mhz" 2>/dev/null) || continue
          rp1=$(cat "$card/gt_RP1_freq_mhz" 2>/dev/null) || continue

          cap=$rp1
          [ "$mode" = high ] && cap=$rp0
          # iGPU has no card VRM.
          [ "$(basename "$(readlink -f "$card/device")")" = ${igpuSlot} ] && cap=$rp0

          # Max never drops below min.
          echo "$rp1" > "$card/gt_min_freq_mhz" 2>/dev/null || true
          echo "$cap" > "$card/gt_max_freq_mhz" 2>/dev/null || true
          echo "$cap" > "$card/gt_boost_freq_mhz" 2>/dev/null || true
        done
      '';

      perms = pkgs.writeShellScript "htpc-gpu-clock-perms" ''
        for f in /sys/class/drm/card*/gt_min_freq_mhz \
                 /sys/class/drm/card*/gt_max_freq_mhz \
                 /sys/class/drm/card*/gt_boost_freq_mhz; do
          [ -e "$f" ] || continue
          ${pkgs.coreutils}/bin/chgrp users "$f" 2>/dev/null || true
          ${pkgs.coreutils}/bin/chmod 0664 "$f" 2>/dev/null || true
        done
      '';
    in
    {
      environment.systemPackages = [ gpuClock ];

      systemd.services.htpc-gpu-clock-perms = {
        description = "Make GPU clock knobs writable for the users group";
        wantedBy = [ "multi-user.target" ];
        after = [ "htpc-gpu-clocks.service" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${perms}";
        };
      };

      # Late cards get the perms.
      services.udev.extraRules = ''
        ACTION=="add|change", SUBSYSTEM=="drm", KERNEL=="card[0-9]*", RUN+="${pkgs.systemd}/bin/systemctl --no-block restart htpc-gpu-clock-perms.service"
      '';
    }
  ;

  # Nightly update and reboot.
  autoUpdate =
    {

      systemd.services.nixlyos-autoupdate = {
        description = "NixlyOS nightly update + reboot (HTPC)";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        path = with pkgs; [ coreutils util-linux nix systemd nixlyos-panel ];
        serviceConfig.Type = "oneshot";
        script = ''
          set -u
          home=/home/${nixlyUser}
          stage="$home/.local/state/nixlyos/stage"
          flake="$home/.local/nixlyos"

          # Failures keep the earlier stage.
          runuser -u ${nixlyUser} -- /run/current-system/sw/bin/nixlyos-stage || true

          sys=$(readlink -f "$stage/result" 2>/dev/null || true)
          [ -n "$sys" ] && [ -e "$sys/bin/switch-to-configuration" ] || exit 0

          cur=$(readlink -f /run/current-system)
          booted=$(readlink -f /run/booted-system)
          [ "$sys" = "$cur" ] && [ "$sys" = "$booted" ] && exit 0

          if [ "$sys" != "$cur" ]; then
            # Keeps nixlyos-update's stamp valid.
            if [ -f "$stage/flake/flake.lock" ]; then
              if [ -f "$flake/profile" ]; then runuser -u ${nixlyUser} -- nixlyos-panel pin || true; fi
              runuser -u ${nixlyUser} -- cp "$stage/flake/flake.lock" "$flake/flake.lock" || true
              rm -f "$flake/pins.nix"
            fi
            nix-env -p /nix/var/nix/profiles/system --set "$sys"
            "$sys/bin/switch-to-configuration" boot
          fi

          # Kernel and session switch together.
          systemctl reboot
        '';
      };

      systemd.timers.nixlyos-autoupdate = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "*-*-* 06:00:00";
          # Never reboot under a viewer.
          Persistent = false;
          AccuracySec = "1min";
        };
      };
    };

  # Couch apps stay in RAM.
  prewarm =
    let
      raFull = retroarchFull;

      # Full runtime closures.
      closure = pkgs.writeClosure [
        raFull
        pkgs.nixlymedia
        pkgs.retroarch-assets
        pkgs.libretro-shaders-slang
      ];

      warmScript = pkgs.writeShellScript "htpc-prewarm" ''
        set -u
        VMTOUCH=${pkgs.vmtouch}/bin/vmtouch

        # Games own RAM and IO.
        ${pkgs.systemd}/bin/systemctl is-active -q nixly-gametune.service && exit 0
        ${pkgs.procps}/bin/pgrep -x wineserver >/dev/null 2>&1 && exit 0
        ${pkgs.procps}/bin/pgrep -x gamescope  >/dev/null 2>&1 && exit 0

        warm() {
          [ -e "$1" ] && "$VMTOUCH" -t -q -m 512M "$1" 2>/dev/null || true
        }

        while IFS= read -r p; do
          warm "$p"
        done < ${closure}

        # Flatpak app and runtime.
        warm /var/lib/flatpak/app/com.nvidia.geforcenow
        rt=$(${pkgs.flatpak}/bin/flatpak info --show-runtime com.nvidia.geforcenow 2>/dev/null || true)
        rt=''${rt#runtime/}
        [ -n "$rt" ] && warm "/var/lib/flatpak/runtime/$rt"
        exit 0
      '';
      # Off the boot path.
      firstWarmScript = pkgs.writeShellScript "htpc-prewarm-first" ''
        set -u
        VMTOUCH=${pkgs.vmtouch}/bin/vmtouch
        while IFS= read -r p; do
          [ -e "$p" ] && "$VMTOUCH" -t -q -m 512M "$p" 2>/dev/null || true
        done < ${closure}
        exit 0
      '';
    in
    {

      systemd.timers.htpc-prewarm-first = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          # Boot app owns the disk.
          OnBootSec = "20s";
          Persistent = false;
        };
      };

      systemd.services.htpc-prewarm-first = {
        description = "Warm the boot HTPC app (RetroArch/nixlymedia) at startup";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${firstWarmScript}";
          Slice = "background.slice";
          Nice = 19;
          CPUSchedulingPolicy = "idle";
          IOSchedulingClass = "idle";
          MemoryHigh = "25%";
        };
      };

      systemd.services.htpc-prewarm = {
        description = "Keep HTPC apps (RetroArch/nixlymedia/GeForce NOW) in RAM";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${warmScript}";
          Slice = "background.slice";
          Nice = 19;
          CPUSchedulingPolicy = "idle";
          IOSchedulingClass = "idle";
          # Reclaims its own pages first.
          MemoryHigh = "25%";
        };
      };

      systemd.timers.htpc-prewarm = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          # After Steam's cold start.
          OnBootSec = "3min";
          OnUnitActiveSec = "10min";
          Persistent = false;
        };
      };
    }
  ;

  # Open ROM pulled into RAM.
  romCache =
    {
      systemd.services.htpc-rom-cache = {
        description = "Pull the ROM the emulator has open into RAM";
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "simple";
          Restart = "always";
          RestartSec = 5;
          # Normal IO, or too late.
          Nice = 5;
          ExecStart = pkgs.writeShellScript "htpc-rom-cache" ''
            set -u
            warmed=""

            while :; do
              for pid in $(${pkgs.procps}/bin/pgrep -f retroarch); do
                for fd in /proc/$pid/fd/*; do
                  rom=$(readlink "$fd" 2>/dev/null) || continue
                  case "$rom" in
                    /mnt/nfs/*) ;;
                    *) continue ;;
                  esac
                  case " $warmed " in
                    *" $rom "*) continue ;;
                  esac
                  warmed="$warmed $rom"
                  # Largest ISO on the share.
                  ${pkgs.vmtouch}/bin/vmtouch -t -q -m 8G "$rom" 2>/dev/null &
                done
              done
              sleep 3
            done
          '';
        };
      };
    };

  # Pads pair themselves.
  controllers =
    let
      btAutopair = pkgs.writeShellScript "htpc-bt-autopair" ''
        set -u
        BT=${pkgs.bluez}/bin/bluetoothctl

        until "$BT" show | ${pkgs.gnugrep}/bin/grep -q "Powered: yes"; do
          sleep 2
        done
        "$BT" pairable on >/dev/null 2>&1 || true

        is_pad() { # $1 mac, $2 name — gamepad by bluez icon/appearance or name
          info=$("$BT" info "$1" 2>/dev/null) || return 1
          printf '%s' "$info" | ${pkgs.gnugrep}/bin/grep -qE \
            "Icon: input-gaming|Appearance: 0x03c" && return 0
          printf '%s' "$2" | ${pkgs.gnugrep}/bin/grep -qiE \
            "controller|gamepad|dualsense|dualshock|wireless gamepad|joy-con|8bitdo|xbox" \
            && return 0
          return 1
        }

        while :; do
          # Bursts keep scanning continuous.
          "$BT" --timeout 12 scan on >/dev/null 2>&1 || true

          paired=$("$BT" devices Paired 2>/dev/null | ${pkgs.gawk}/bin/awk '{print $2}')
          "$BT" devices 2>/dev/null | while read -r _ mac name; do
            [ -n "$mac" ] || continue
            printf '%s\n' "$paired" | ${pkgs.gnugrep}/bin/grep -qiF "$mac" && continue
            is_pad "$mac" "$name" || continue
            echo "pairing new controller: $name ($mac)"
            "$BT" pair "$mac" >/dev/null 2>&1 || continue
            "$BT" trust "$mac" >/dev/null 2>&1 || true
            "$BT" connect "$mac" >/dev/null 2>&1 || true
          done
          sleep 3
        done
      '';

      # Xbox dongles that boot dead.
      xoneRecover = pkgs.writeShellScript "htpc-xone-recover" ''
        set -u
        # Normal probe finishes first.
        sleep 8
        for try in 1 2 3; do
          fixed=1
          for dev in /sys/bus/usb/devices/*; do
            [ -f "$dev/idVendor" ] && [ -f "$dev/idProduct" ] || continue
            vid=$(cat "$dev/idVendor"); pid=$(cat "$dev/idProduct")
            [ "$vid" = "045e" ] || continue
            case "$pid" in 02fe|0719) ;; *) continue ;; esac
            # Healthy dongles have a driver.
            bound=""
            for intf in "$dev":*/driver; do
              [ -e "$intf" ] || continue
              case "$(basename "$(readlink -f "$intf")")" in
                *xone*|xpad*) bound=1 ;;
              esac
            done
            if [ -z "$bound" ]; then
              echo "xone dongle at $dev unbound — software re-plug (try $try)"
              echo 0 > "$dev/authorized" 2>/dev/null || true
              sleep 2
              echo 1 > "$dev/authorized" 2>/dev/null || true
              fixed=0
            fi
          done
          [ "$fixed" = 1 ] && exit 0
          sleep 5
        done
        exit 0
      '';
    in
    {

      systemd.services.htpc-bt-autopair = {
        description = "Auto-pair any Bluetooth game controller in pairing mode";
        after = [ "bluetooth.service" ];
        wants = [ "bluetooth.service" ];
        wantedBy = [ "bluetooth.target" ];
        serviceConfig = {
          Type = "simple";
          ExecStart = "${btAutopair}";
          Restart = "always";
          RestartSec = 5;
          Nice = 10;
        };
      };

      systemd.services.htpc-xone-recover = {
        description = "Re-plug a dead Xbox Wireless dongle via sysfs";
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${xoneRecover}";
        };
      };

      # Hotplugged dongles too.
      services.udev.extraRules = ''
        ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="045e", ATTR{idProduct}=="02fe", TAG+="systemd", ENV{SYSTEMD_WANTS}+="htpc-xone-recover.service"
        ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="045e", ATTR{idProduct}=="0719", TAG+="systemd", ENV{SYSTEMD_WANTS}+="htpc-xone-recover.service"
      '';
    }
  ;

  # Pads inside the flatpak.
  geforceNow =
    {

      systemd.services.geforce-now-controller-access = {
        description = "Flatpak override: controller access for GeForce NOW";
        wantedBy = [ "multi-user.target" ];
        after = [ "geforce-now-install.service" ];
        path = [ pkgs.flatpak ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          flatpak override --device=all --filesystem=/run/udev:ro com.nvidia.geforcenow
        '';
      };
    };

  # Couch traffic first.
  qos =
    {
      networking.nftables.tables.htpc-qos = {
        family = "inet";
        content = ''
          chain postrouting {
            type filter hook postrouting priority mangle; policy accept;

            # Steam game and voice.
            udp dport 27000-27100 ip dscp set ef
            udp dport 27000-27100 ip6 dscp set ef

            # RetroArch netplay.
            udp dport 55435 ip dscp set ef
            udp dport 55435 ip6 dscp set ef

            # nixlymedia stream, WMM video.
            tcp dport 8080 ip dscp set cs3
            tcp dport 8080 ip6 dscp set cs3
            udp dport 8081 ip dscp set cs3
            udp dport 8081 ip6 dscp set cs3
          }
        '';
      };
    };

  # Small receive queues.
  rxBuffers =
    {
      boot.kernel.sysctl = {
        "net.core.rmem_max" = lib.mkForce 8388608;
        "net.ipv4.tcp_rmem" = lib.mkForce "4096 262144 8388608";
      };
    };

  # Desktop extras off.
  trim =
    {

      # No tablets on a TV.
      hardware.opentabletdriver.enable = lib.mkForce false;
      hardware.opentabletdriver.daemon.enable = lib.mkForce false;

      # No file manager here.
      services.tumbler.enable = lib.mkForce false;

      # Never sleeps mid-stream.
      systemd.targets.sleep.enable = false;
      systemd.targets.suspend.enable = false;
      systemd.targets.hibernate.enable = false;
      systemd.targets.hybrid-sleep.enable = false;
    };

  # Blank keyring under autologin.
  keyring =
    let
      sanitize = pkgs.writeShellScript "nixly-keyring-sanitize" ''
            set -u
            K="$HOME/.local/share/keyrings"
            ${pkgs.coreutils}/bin/mkdir -p "$K"
            ${pkgs.coreutils}/bin/chmod 700 "$K"
            for f in "$K"/*.keyring; do
              [ -f "$f" ] || continue
              if ${pkgs.coreutils}/bin/head -c12 "$f" \
                  | ${pkgs.gnugrep}/bin/grep -q "GnomeKeyring"; then
                ${pkgs.coreutils}/bin/mv "$f" \
                  "$f.locked-$(${pkgs.coreutils}/bin/date +%Y%m%d-%H%M%S)"
              fi
            done
            if [ ! -f "$K/login.keyring" ]; then
              ${pkgs.coreutils}/bin/cat > "$K/login.keyring" <<'EOF'
        [keyring]
        display-name=Login
        ctime=0
        mtime=0
        lock-on-idle=false
        lock-after=false
        EOF
              ${pkgs.coreutils}/bin/chmod 600 "$K/login.keyring"
            fi
      '';
    in
    {
      systemd.user.services.nixly-keyring-sanitize = {
        description = "Blank login keyring so autologin never prompts";
        wantedBy = [ "default.target" ];
        before = [ "gnome-keyring-daemon.service" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${sanitize}";
        };
      };
    }
  ;

in
{
  imports = [
    login
    session
    media
    audio
    hdmiAudio
    biosSync
    retroarch4k
    gpuClocks
    gpuClock
    autoUpdate
    prewarm
    romCache
    controllers
    geforceNow
    qos
    rxBuffers
    trim
    keyring
  ];

  assertions = [{
    assertion = config.nixlyos.mode == "htpc";
    message = "HTPC-modulen hører til profiler med plattform htpc.";
  }];
}
$nix$),
('hardware', 'Maskinvare', 'CPU, grafikk, hovedkort, virtualisering og tilbehør, valgt av maskinvaren.', true, 11, $nix${ config, lib, pkgs, inputs, hwData, ... }:

let
  gpu = hwData.detected;
  board = hwData.profile;
  blackwell = gpu.nvidiaArch == "blackwell_plus";
  # Older detect-hw names.
  renamedGpus = { nvidia_intel = "nvidia_hybrid"; };

  # Shared Mesa session tuning.
  mesaCache = {
    mesa_glthread = "true";
    # Eviction causes recompile stutter.
    MESA_SHADER_CACHE_MAX_SIZE = "10G";
  };

  waylandApps = {
    NIXOS_OZONE_WL = "1";
    QT_QPA_PLATFORM = "wayland";
    SDL_VIDEODRIVER = "wayland";
    MOZ_ENABLE_WAYLAND = "1";
  };

  nvidiaCache = {
    __GL_VRR_ALLOWED = "1";
    __GL_GSYNC_ALLOWED = "1";
    __GL_SHADER_DISK_CACHE = "1";
    __GL_SHADER_DISK_CACHE_SIZE = "10737418240";
    __GL_SHADER_DISK_CACHE_SKIP_CLEANUP = "1";
    ELECTRON_OZONE_PLATFORM_HINT = "auto";
  };

  glvnd = {
    enable = true;
    enable32Bit = true;
    extraPackages = with pkgs; [
      vulkan-loader
      libGL
      libglvnd
    ];
    extraPackages32 = with pkgs.pkgsi686Linux; [
      vulkan-loader
      libGL
      libglvnd
    ];
  };

  nvidiaModules = [ "nvidia" "nvidia_uvm" "nvidia_modeset" "nvidia_drm" ];

  nvidiaParams = [
    "nvidia_drm.modeset=1"
    "nvidia_drm.fbdev=1"
    # Skip zeroing new GPU memory.
    "nvidia.NVreg_InitializeSystemMemoryAllocations=0"
    # No-op before Ampere vbios.
    "nvidia.NVreg_EnableResizableBar=1"
  ];

  # GBM for the greeter.
  nvidiaSession = {
    LIBVA_DRIVER_NAME = "nvidia";
    __GLX_VENDOR_LIBRARY_NAME = "nvidia";
    GBM_BACKEND = "nvidia-drm";
  };

  # Data names modules, never paths.
  machine =
    let
      hw = inputs.nixos-hardware.nixosModules;
      model = lib.findFirst (n: builtins.hasAttr n hw) null board.candidates;
      generic = builtins.filter (n: builtins.hasAttr n hw) board.generic;
      missing = builtins.filter (n: !(builtins.hasAttr n hw)) board.generic;
    in
    lib.warnIf (missing != [ ])
      "hw/profile.nix: ukjente nixos-hardware-moduler: ${toString missing}"
      {
        imports =
          map (n: hw.${n}) generic
          ++ lib.optional (model != null) hw.${model}
          ++ lib.optionals board.msiEc [ msiEc thermalLimits ]
          ++ [ fans ];

        # TLP would own the governor.
        services.tlp.enable = lib.mkIf board.isLaptop (lib.mkForce false);
      };

  # SuperIO chips nothing probes.
  fans = {
    boot.kernelModules = [ "nct6775" "it87" ];
    # ACPI already claims the range.
    boot.extraModprobeConfig = ''
      options it87 ignore_resource_conflict=1
    '';
  };

  msiEc =
    let
      kp = config.boot.kernelPackages;
      msiEcPkg = if kp ? msi-ec then kp.msi-ec else if kp ? msi_ec then kp.msi_ec else null;

      # Firmware versions the driver knows.
      fwList = pkgs.runCommand "msi-ec-firmware-list" { } ''
        grep -ohE '"[0-9A-Z]+E[A-Z0-9]+\.[0-9]+"' ${msiEcPkg.src}/msi-ec.c \
          | tr -d '"' | sort -u > $out
      '';

      # Pins unlisted firmware to a sibling.
      autoload = pkgs.writeShellScript "msi-ec-autoload" ''
        set -u
        export PATH=${lib.makeBinPath [ pkgs.kmod pkgs.coreutils pkgs.gnugrep ]}

        if modprobe msi-ec 2>/dev/null && [ -d /sys/devices/platform/msi-ec ]; then
          echo "msi-ec: EC-firmware stoettet direkte"
          exit 0
        fi

        modprobe ec_sys write_support=1 2>/dev/null || true
        io=/sys/kernel/debug/ec/ec0/io
        if [ ! -r "$io" ]; then
          echo "msi-ec: fant ikke $io — kan ikke lese EC-firmware"
          exit 0
        fi

        ver=$(dd if="$io" bs=1 skip=160 count=12 status=none | tr -cd '[:alnum:].')
        case "$ver" in
          *.*) ;;
          *) echo "msi-ec: ulesbar EC-firmware ('$ver')"; exit 0 ;;
        esac

        cand=$(grep -m1 "^''${ver%.*}\." ${fwList} || true)
        if [ -z "$cand" ]; then
          echo "msi-ec: EC-firmware $ver ikke stoettet (ingen konfig for ''${ver%.*})"
          exit 0
        fi

        echo "msi-ec: EC-firmware $ver ukjent for driveren — bruker konfig $cand"
        modprobe msi-ec firmware="$cand" || echo "msi-ec: lasting feilet"
        exit 0
      '';
    in
    {
      boot.extraModulePackages = lib.mkAfter (lib.optional (msiEcPkg != null) msiEcPkg);

      # msi-ec-autoload loads msi-ec.
      boot.kernelModules = lib.mkAfter [ "ec_sys" ];

      # Fan curves write the EC.
      boot.extraModprobeConfig = lib.mkAfter ''
        options ec_sys write_support=1
      '';

      services.udev.extraRules = ''
        ACTION=="add|change", SUBSYSTEM=="platform", KERNEL=="msi-ec", RUN+="/bin/sh -c 'chmod 0666 /sys/devices/platform/msi-ec/fan_mode /sys/devices/platform/msi-ec/shift_mode /sys/devices/platform/msi-ec/cooler_boost 2>/dev/null || true'"
      '';

      # Fans popup's validated EC writer.
      systemd.services.nixly-fand = {
        description = "nixlytile fan control helper";
        wantedBy = [ "multi-user.target" ];
        after = [ "systemd-modules-load.service" "msi-ec-autoload.service" ];
        serviceConfig = {
          Type = "exec";
          ExecStart = "${pkgs.nixlytile}/bin/nixly-fand";
          Restart = "on-failure";
          RestartSec = 5;
          NoNewPrivileges = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          PrivateTmp = true;
          PrivateNetwork = true;
          ProtectHostname = true;
          ProtectKernelModules = true;
          ProtectKernelLogs = true;
          ProtectControlGroups = true;
          RestrictAddressFamilies = [ "AF_UNIX" ];
          RestrictNamespaces = true;
          RestrictRealtime = true;
          LockPersonality = true;
          MemoryDenyWriteExecute = true;
          SystemCallArchitectures = "native";
          SystemCallFilter = [ "@system-service" "@raw-io" ];
          CapabilityBoundingSet = [ "CAP_SYS_RAWIO" "CAP_DAC_OVERRIDE" "CAP_CHOWN" ];
          # Control socket lives here.
          ReadWritePaths = [ "/run" ];
        };
      };

      systemd.services.msi-ec-autoload = lib.mkIf (msiEcPkg != null) {
        description = "Load msi-ec with a matching EC firmware configuration";
        after = [ "systemd-modules-load.service" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = autoload;
        };
      };
    };

  thermalLimits =
    let
      # Throttle before acpitz cuts power.
      tccOffset = 10;
      # TCC limits, not RAPL.
      powerLimit = 200000000;

      apply = pkgs.writeShellScript "thermal-limits" ''
        for f in /sys/bus/pci/drivers/proc_thermal/*/tcc_offset_degree_celsius; do
          [ -e "$f" ] && echo ${toString tccOffset} > "$f"
        done
        for d in /sys/class/powercap/intel-rapl:0 /sys/class/powercap/intel-rapl-mmio:0; do
          [ -d "$d" ] || continue
          echo ${toString powerLimit} > "$d/constraint_0_power_limit_uw"
          echo ${toString powerLimit} > "$d/constraint_1_power_limit_uw"
        done
      '';
    in
    {
      # Reapply on device add, resume.
      services.udev.extraRules = ''
        ACTION=="add|bind", SUBSYSTEM=="pci", DRIVER=="proc_thermal", RUN+="${pkgs.systemd}/bin/systemctl --no-block restart thermal-limits.service"
        ACTION=="add", SUBSYSTEM=="powercap", KERNEL=="intel-rapl:0|intel-rapl-mmio:0", RUN+="${pkgs.systemd}/bin/systemctl --no-block restart thermal-limits.service"
      '';

      systemd.services.thermal-limits = {
        description = "Apply CPU temperature and power limits";
        wantedBy = [ "multi-user.target" "post-resume.target" ];
        # thermald keeps what it saw.
        before = [ "thermald.service" ];
        after = [ "post-resume.target" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = apply;
        };
      };
    };

  cpus = {
    intel = {
      hardware.cpu.intel.updateMicrocode = true;

      boot = {
        kernelModules = [ "kvm-intel" ];
        # VT-d on, never passthrough.
        kernelParams = lib.mkBefore [
          "intel_pstate=active"
          "intel_iommu=on"
        ];
      };

      services.thermald.enable = true;
      # It overrode the governor.
      services.power-profiles-daemon.enable = false;
      environment.systemPackages = with pkgs; [
        lm_sensors
        cpufrequtils
      ];
    };

    amd = {
      hardware.cpu.amd.updateMicrocode = true;

      boot = {
        kernelModules = [ "kvm-amd" ];
        # AMD-Vi on, never passthrough.
        kernelParams = lib.mkBefore [
          "amd_pstate=active"
          "amd_iommu=on"
        ];
      };
      environment.systemPackages = with pkgs; [
        lm_sensors
        cpufrequtils
      ];
      services.power-profiles-daemon.enable = false;
    };

    # SoC firmware ships CPU fixes.
    arm = {
      environment.systemPackages = with pkgs; [
        lm_sensors
      ];
      services.power-profiles-daemon.enable = false;
    };
  };

  gpus = {
    intel =
      let
        # Every DG2 device ID.
        dg2 = [
          "5690"
          "5691"
          "5692"
          "5693"
          "5694"
          "5695"
          "5696"
          "5697"
          "56a0"
          "56a1"
          "56a2"
          "56a3"
          "56a4"
          "56a5"
          "56a6"
          "56b0"
          "56b1"
          "56b2"
          "56b3"
          "56ba"
          "56bb"
          "56bc"
          "56bd"
          "56be"
          "56bf"
          "56c0"
          "56c1"
          "56c2"
        ];
        drives = gpu.primary == "intel";
      in
      {
        hardware.graphics = {
          enable = true;
          enable32Bit = true;
          extraPackages = with pkgs; [
            vulkan-loader
            intel-media-driver
            vpl-gpu-rt
            intel-compute-runtime
            ocl-icd
            libvdpau-va-gl
          ];
          extraPackages32 = with pkgs.pkgsi686Linux; [
            vulkan-loader
            intel-media-driver
            libvdpau-va-gl
          ];
        };

        # Battlemage is xe-only.
        boot.initrd.kernelModules = lib.mkIf drives [ "i915" "xe" ];

        boot.kernelParams = [
          # iHD on xe SIGBUSes.
          "i915.force_probe=${lib.concatStringsSep "," dg2}"
          "xe.force_probe=${lib.concatMapStringsSep "," (id: "!${id}") dg2}"
          # Slow TVs keep their mode.
          "i915.fastboot=1"
        ];

        services.xserver.videoDrivers = [ "modesetting" ];

        # GuC and HuC blobs.
        hardware.enableRedistributableFirmware = true;

        # DG2 HDMI sink vanished idle.
        services.udev.extraRules = ''
          ACTION=="add", SUBSYSTEM=="pci", ATTR{class}=="0x040300", ATTR{vendor}=="0x8086", ATTR{device}=="0x4f9?", ATTR{power/control}="on"
          ACTION=="add", SUBSYSTEM=="hdaudio", ATTRS{vendor}=="0x8086", ATTRS{device}=="0x4f9?", ATTR{power/control}="on"
        '';

        environment.systemPackages = with pkgs; [
          vulkan-tools
          libva-utils
          intel-gpu-tools
        ];

        environment.sessionVariables = mesaCache // waylandApps // {
          # Only the session GPU.
          LIBVA_DRIVER_NAME = lib.mkIf drives "iHD";
        };
      };

    # Gen8 to Gen11.
    intel_igpu = {
      hardware.graphics = {
        enable = true;
        enable32Bit = true;
        extraPackages = with pkgs; [
          intel-media-driver
          intel-vaapi-driver
          libvdpau-va-gl
        ];
        extraPackages32 = with pkgs.pkgsi686Linux; [
          intel-media-driver
          intel-vaapi-driver
          libvdpau-va-gl
        ];
      };

      boot.initrd.kernelModules = lib.mkIf (gpu.primary == "intel") [ "i915" ];

      # EDID mode survives without flicker.
      boot.kernelParams = [ "i915.fastboot=1" ];

      # FBC stormed eDP commits.
      boot.extraModprobeConfig = ''
        options i915 enable_guc=3 enable_fbc=0
      '';

      hardware.enableRedistributableFirmware = true;

      environment.sessionVariables = mesaCache;
    };

    # Gen7.5 and older, i965 only.
    intel_legacy =
      let
        drives = gpu.primary == "intel";
      in
      {
        hardware.graphics = {
          enable = true;
          enable32Bit = true;
          extraPackages = with pkgs; [
            intel-vaapi-driver
            libvdpau-va-gl
          ];
          extraPackages32 = with pkgs.pkgsi686Linux; [
            vulkan-loader
            intel-vaapi-driver
            libvdpau-va-gl
          ];
        };

        services.xserver.videoDrivers = [ "modesetting" ];

        boot.initrd.kernelModules = lib.mkIf drives [ "i915" ];

        hardware.enableRedistributableFirmware = true;

        environment.systemPackages = with pkgs; [
          vulkan-tools
          libva-utils
          intel-gpu-tools
        ];

        environment.sessionVariables = waylandApps // {
          LIBVA_DRIVER_NAME = lib.mkIf drives "i965";
          mesa_glthread = "true";
          ELECTRON_OZONE_PLATFORM_HINT = "auto";
        };
      };

    amd =
      let
        drives = gpu.primary == "amd";
      in
      {
        hardware.graphics = {
          enable = true;
          enable32Bit = true;
          extraPackages = with pkgs; [
            vulkan-loader
            libva-vdpau-driver
            libvdpau-va-gl
          ];
          extraPackages32 = with pkgs.pkgsi686Linux; [
            vulkan-loader
            libva-vdpau-driver
            libvdpau-va-gl
          ];
        };

        # Overdrive for fan and power.
        boot.kernelParams = [ "amdgpu.ppfeaturemask=0xffffffff" ];

        environment.systemPackages = with pkgs; [
          vulkan-tools
          libva-utils
          amdgpu_top
        ];

        environment.sessionVariables = mesaCache // waylandApps // {
          LIBVA_DRIVER_NAME = lib.mkIf drives "radeonsi";
          VDPAU_DRIVER = lib.mkIf drives "radeonsi";
          # amdvlk never hijacks the ICD.
          AMD_VULKAN_ICD = "RADV";
        };
      };

    # SI and CIK forced onto amdgpu.
    amd_legacy = {
      services.xserver.videoDrivers = [ "modesetting" ];

      hardware.graphics = {
        enable = true;
        enable32Bit = true;
        extraPackages = with pkgs; [
          libva-vdpau-driver
          libvdpau-va-gl
        ];
        extraPackages32 = with pkgs.pkgsi686Linux; [
          vulkan-loader
          libva-vdpau-driver
          libvdpau-va-gl
        ];
      };

      boot.kernelParams = [
        "radeon.si_support=0"
        "amdgpu.si_support=1"
        "radeon.cik_support=0"
        "amdgpu.cik_support=1"
      ];

      hardware.enableRedistributableFirmware = true;

      environment.systemPackages = with pkgs; [
        vulkan-tools
        libva-utils
      ];

      # libva picks radeonsi or r600.
      environment.sessionVariables = waylandApps // {
        mesa_glthread = "true";
        ELECTRON_OZONE_PLATFORM_HINT = "auto";
      };

      warnings = [
        "gpu/amd_legacy.nix: gammelt AMD-kort (PCI-ID i pre-GCN/GCN1/GCN2-omraadet). RADV/Vulkan krever GCN1 eller nyere — er kortet TeraScale eller eldre, kjoerer det OpenGL-only, og spill via Proton fungerer ikke."
      ];
    };

    # PRIME offload behind the iGPU.
    nvidia_hybrid =
      let
        # Mesa Vulkan ICDs of the iGPU.
        icds = { intel = [ "intel_icd" "intel_hasvk_icd" ]; amd = [ "radeon_icd" ]; }.${gpu.primary};
      in
      {
        imports = [ nvidiaAcReload ];

        services.xserver.videoDrivers = [ "nvidia" ];

        nixpkgs.overlays = [
          (final: prev: {
            # Blender and Gaea opt back into dGPU.
            Blender_bin_lts = final.symlinkJoin {
              inherit (prev.Blender_bin_lts) name meta;
              paths = [ prev.Blender_bin_lts ];
              nativeBuildInputs = [ final.makeWrapper ];
              postBuild = ''
                wrapProgram $out/bin/blender \
                  --unset VK_DRIVER_FILES \
                  --set __NV_PRIME_RENDER_OFFLOAD 1 \
                  --set __NV_PRIME_RENDER_OFFLOAD_PROVIDER NVIDIA-G0 \
                  --set __GLX_VENDOR_LIBRARY_NAME nvidia \
                  --set __VK_LAYER_NV_optimus NVIDIA_only
              '';
            };
            gaea = final.symlinkJoin {
              inherit (prev.gaea) name meta;
              paths = [ prev.gaea ];
              nativeBuildInputs = [ final.makeWrapper ];
              postBuild = ''
                wrapProgram $out/bin/gaea \
                  --unset VK_DRIVER_FILES \
                  --set __VK_LAYER_NV_optimus NVIDIA_only
              '';
            };
          })
        ];

        hardware.graphics = glvnd;

        hardware.nvidia = {
          modesetting.enable = true;
          # Lets the driver drop the GPU.
          nvidiaPersistenced = false;
          powerManagement.enable = true;
          # D3cold without offload clients.
          powerManagement.finegrained = true;
          # Blackwell runs only open modules.
          open = blackwell;
          nvidiaSettings = false;
          package = lib.mkDefault config.boot.kernelPackages.nvidiaPackages.latest;
          # nvidia-powerd pinned 10 W.
          dynamicBoost.enable = false;
          # Enforces the SBIOS power clamp.
          gsp.enable = blackwell;
          # reverseSync black-screened the panel.
          prime = {
            offload.enable = true;
            offload.enableOffloadCmd = true;
            intelBusId = lib.mkIf (gpu.primary == "intel") gpu.intel;
            amdgpuBusId = lib.mkIf (gpu.primary == "amd") gpu.amd;
            nvidiaBusId = gpu.nvidia;
          };
        };

        boot = {
          # iGPU owns the boot console.
          kernelModules = nvidiaModules;
          kernelParams = nvidiaParams;
        };

        environment.systemPackages = with pkgs; [
          vulkan-tools
          libva-utils
          nvtopPackages.full
          egl-wayland
          nvidia-vaapi-driver
        ];

        # Probes would wake the dGPU.
        environment.sessionVariables = nvidiaCache // {
          VK_DRIVER_FILES = lib.concatStringsSep ":" (
            map (n: "/run/opengl-driver/share/vulkan/icd.d/${n}.x86_64.json") icds
              ++ map (n: "/run/opengl-driver-32/share/vulkan/icd.d/${n}.i686.json") icds
          );
          __EGL_VENDOR_LIBRARY_FILENAMES =
            "/run/opengl-driver/share/glvnd/egl_vendor.d/50_mesa.json:"
              + "/run/opengl-driver-32/share/glvnd/egl_vendor.d/50_mesa.json";
          __GL_THREADED_OPTIMIZATIONS = "1";
          MESA_SHADER_CACHE_MAX_SIZE = "10G";
        };
      };

    # NVIDIA drives the session.
    nvidia_only = {
      services.xserver.videoDrivers = [ "nvidia" ];

      hardware.graphics = glvnd;

      hardware.nvidia = {
        modesetting.enable = true;
        nvidiaPersistenced = true;
        powerManagement.enable = false;
        powerManagement.finegrained = false;
        open = blackwell;
        nvidiaSettings = false;
        # custom/modules.nix may pick previous.
        package = lib.mkDefault config.boot.kernelPackages.nvidiaPackages.latest;
      };

      boot = {
        # Takes the console before efifb.
        initrd.kernelModules = nvidiaModules;
        kernelModules = nvidiaModules;
        kernelParams = nvidiaParams
          # GSP wedges after channel resets.
          ++ lib.optional (!blackwell) "nvidia.NVreg_EnableGpuFirmware=0";
      };

      environment.systemPackages = with pkgs; [
        vulkan-tools
        libva-utils
        egl-wayland
        nvidia-vaapi-driver
        nvtopPackages.full
      ];

      environment.variables = nvidiaSession;

      # Threaded optimizations hang GL here.
      environment.sessionVariables = nvidiaCache // {
        NIXLY_NVIDIA_PRIMARY = lib.mkIf (gpu.primary == "nvidia") "1";
      };

      # PAM env import may race.
      systemd.services.display-manager.environment = nvidiaSession;
    };

    # Branch picked by detect-hw.
    nvidia_legacy =
      let
        np = config.boot.kernelPackages.nvidiaPackages;
        branch = if builtins.hasAttr gpu.nvidiaBranch np then gpu.nvidiaBranch else "latest";
        # nixlytile and SDDM need GBM.
        gbmOk = !(builtins.elem branch [ "legacy_390" "legacy_340" ]);
        hybrid = gpu.primary != "nvidia";
      in
      {
        services.xserver.videoDrivers = [ "nvidia" ];

        hardware.graphics = glvnd;

        hardware.nvidia = {
          package = np.${branch};
          modesetting.enable = gbmOk;
          # Oldest packages lack these binaries.
          nvidiaPersistenced = gbmOk;
          nvidiaSettings = false;
          powerManagement.enable = false;
          powerManagement.finegrained = false;
          # Open modules start at Turing.
          open = false;

          prime = lib.mkIf (hybrid && gbmOk) {
            offload.enable = true;
            offload.enableOffloadCmd = true;
            intelBusId = lib.mkIf (gpu.primary == "intel") gpu.intel;
            amdgpuBusId = lib.mkIf (gpu.primary == "amd") gpu.amd;
            nvidiaBusId = gpu.nvidia;
          };
        };

        boot = {
          kernelModules = [ "nvidia" "nvidia_uvm" "nvidia_modeset" ]
            ++ lib.optional gbmOk "nvidia_drm";

          kernelParams =
            [ "nvidia.NVreg_UsePageAttributeTable=1" ]
            ++ lib.optionals gbmOk [
              "nvidia_drm.modeset=1"
              "nvidia_drm.fbdev=1"
              "nvidia.NVreg_EnableResizableBar=1"
              "nvidia.NVreg_InitializeSystemMemoryAllocations=0"
            ];
        };

        # VA-API needs 470+.
        environment.systemPackages = with pkgs; [
          vulkan-tools
          libva-utils
          nvtopPackages.full
        ] ++ lib.optionals gbmOk [
          egl-wayland
          nvidia-vaapi-driver
        ];

        environment.sessionVariables = nvidiaCache // {
          __GL_THREADED_OPTIMIZATIONS = "1";
          NIXLY_NVIDIA_PRIMARY = lib.mkIf (gbmOk && !hybrid) "1";
        };

        environment.variables = lib.mkIf (gbmOk && !hybrid) nvidiaSession;

        systemd.services.display-manager.environment = lib.mkIf (gbmOk && !hybrid) nvidiaSession;

        warnings =
          lib.optional (!gbmOk)
            "gpu/nvidia_legacy.nix: ${branch} har ingen GBM-stoette. SDDM Wayland og nixlytile starter ikke paa dette kortet (arkitektur: ${gpu.nvidiaArch})."
          ++ lib.optional (branch != "latest")
            "gpu/nvidia_legacy.nix: ${branch} bygger bare mot eldre kernel-serier. Feiler kernel-modulen, maa boot.kernelPackages pinnes lavere enn zen/cachyos-valget i boot.nix.";
      };

    # Proprietary branches are broken.
    nvidia_nouveau = {
      services.xserver.videoDrivers = [ "modesetting" ];

      hardware.graphics = {
        enable = true;
        enable32Bit = true;
        extraPackages = with pkgs; [
          libvdpau-va-gl
        ];
        extraPackages32 = with pkgs.pkgsi686Linux; [
          vulkan-loader
          libvdpau-va-gl
        ];
      };

      boot.initrd.kernelModules = [ "nouveau" ];

      hardware.enableRedistributableFirmware = true;

      environment.systemPackages = with pkgs; [
        vulkan-tools
        libva-utils
        mesa-demos
      ];

      environment.sessionVariables = waylandApps // {
        ELECTRON_OZONE_PLATFORM_HINT = "auto";
      };

      warnings = [
        "gpu/nvidia_nouveau.nix: kortet (arkitektur: ${gpu.nvidiaArch}) stoettes bare av NVIDIA legacy_390/legacy_340, som er broken i nixpkgs paa moderne kernel. Bruker nouveau — spillytelse er langt under den proprietaere driveren, og reclocking er begrenset."
      ];
    };
  };

  # Charger dropouts cap it at 10 W.
  nvidiaAcReload =
    let
      reload = pkgs.writeShellScript "nvidia-ac-reload" ''
        export PATH=${pkgs.kmod}/bin:${pkgs.coreutils}/bin:${config.hardware.nvidia.package.bin}/bin

        on_mains() {
          for s in /sys/class/power_supply/*; do
            [ "$(cat "$s/type")" = Mains ] && [ "$(cat "$s/online")" = 1 ] && return 0
          done
          return 1
        }

        capped() {
          IFS=', ' read -r cur def < <(nvidia-smi \
            --query-gpu=enforced.power.limit,power.default_limit --format=csv,noheader,nounits)
          [ "''${cur%.*}" -lt "''${def%.*}" ]
        }

        # Only the stack holds references.
        idle() {
          for m in nvidia_drm nvidia_uvm nvidia_modeset nvidia; do
            set -- /sys/module/$m/holders/*
            [ -e "$1" ] || set --
            [ "$(cat /sys/module/$m/refcnt)" -eq $# ] || return 1
          done
        }

        sleep 2
        on_mains && capped || exit 0
        while on_mains; do
          if idle; then
            modprobe -r nvidia_drm nvidia_uvm nvidia_modeset nvidia
            modprobe nvidia_drm
            modprobe nvidia_uvm
            exit 0
          fi
          sleep 1
        done
      '';
    in
    {
      services.udev.extraRules = ''
        ACTION=="change", SUBSYSTEM=="power_supply", ATTR{type}=="Mains", ATTR{online}=="1", RUN+="${pkgs.systemd}/bin/systemctl --no-block start nvidia-ac-reload.service"
      '';

      systemd.services.nvidia-ac-reload = {
        description = "Reload the NVIDIA driver when capped on mains";
        wantedBy = [ "multi-user.target" ];
        after = [ "systemd-modules-load.service" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = reload;
        };
      };
    };

  # Mainline Mesa drives every SBC.
  soc = {
    hardware.graphics.enable = true;
    hardware.enableRedistributableFirmware = true;
  };

  # Rendering always comes up.
  guest = {
    hardware.graphics.enable = true;
    environment.sessionVariables.NIXLY_NO_HARDWARE_CURSORS = "1";
  };

  guests = {
    hyperv = {
      imports = [ guest ];
      virtualisation.hypervGuest.enable = true;
    };

    kvm = {
      imports = [ guest ];
      services.qemuGuest.enable = true;
      services.spice-vdagentd.enable = true;
      # Root disk never waits.
      boot.initrd.availableKernelModules = [
        "virtio_pci"
        "virtio_blk"
        "virtio_scsi"
        "virtio_net"
        "virtio_gpu"
      ];
    };

    # Tools break on kernel bumps.
    parallels = {
      imports = [ guest ];
    };

    virtualbox = {
      imports = [ guest ];
      virtualisation.virtualbox.guest.enable = true;
    };

    vmware = {
      imports = [ guest ];
      virtualisation.vmware.guest.enable = true;
      boot.initrd.availableKernelModules = [
        "mptspi"
        "vmw_pvscsi"
      ];
    };
  };

  # Boot-time pick in /run/nixly/gpu.env.
  gpuSelect = {
    environment.systemPackages = [ pkgs.nixly-dgpu ];

    systemd.services.nixly-gpu-select = {
      description = "Pick the GPU for dGPU offload";
      wantedBy = [ "multi-user.target" ];
      before = [ "display-manager.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        RuntimeDirectory = "nixly";
        RuntimeDirectoryPreserve = "yes";
        # Coldplug binds the drivers.
        ExecStartPre = "-${pkgs.systemd}/bin/udevadm settle --timeout=10";
        ExecStart = "${lib.getExe pkgs.nixly-gpu-select} /run/nixly/gpu.env";
      };
    };
  };

  # Heavy laptop apps on the dGPU.
  offload =
    let
      # Browsers stay on the iGPU.
      joined = {
        vlc = { bins = [ "vlc" "cvlc" "nvlc" "qvlc" "rvlc" "svlc" ]; };
        nixlymedia = { bins = [ "nixlymedia" ]; };
        lutris = { bins = [ "lutris" ]; };
        Blender_bin_lts = { bins = [ "blender" ]; };
        gaea = { bins = [ "gaea" ]; };
      };

      wrapBins = final: { bins, nodeArg ? null }: lib.concatMapStrings
        (bin: ''
          mv "$out/bin/${bin}" "$out/bin/.${bin}-dgpu"
          makeBinaryWrapper ${final.nixly-dgpu}/bin/nixly-dgpu "$out/bin/${bin}" ${
            lib.optionalString (nodeArg != null) "--add-flag --node-arg --add-flag ${nodeArg}"
          } --add-flag "$out/bin/.${bin}-dgpu"
        '')
        bins;

      dgpuJoin = final: pkg: spec: final.symlinkJoin {
        inherit (pkg) name meta;
        paths = [ pkg ];
        nativeBuildInputs = [ final.makeBinaryWrapper ];
        postBuild = ''
          # FHS envs link the directory.
          if [ -L "$out/share/applications" ]; then
            apps=$(readlink -f "$out/share/applications")
            rm "$out/share/applications"
            mkdir "$out/share/applications"
            ln -s "$apps"/* "$out/share/applications/"
          fi
          # Launchers hardcode the unwrapped path.
          for d in $out/share/applications/*.desktop; do
            [ -e "$d" ] || continue
            real=$(readlink -f "$d")
            rm "$d"
            substitute "$real" "$d" --replace-quiet "${pkg}/bin/" "$out/bin/"
          done
        '' + wrapBins final spec;
      };

      # Already symlinkJoin wrappers.
      dgpuAppend = final: drv: spec: drv.overrideAttrs (old: {
        nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ final.makeBinaryWrapper ];
        buildCommand = old.buildCommand + wrapBins final spec;
      });
    in
    lib.mkIf hwData.dmi.isLaptop {
      # Outermost wrapper.
      nixpkgs.overlays = lib.mkAfter [
        (final: prev: lib.mapAttrs (name: dgpuJoin final prev.${name}) joined // {
          # Keeps mpv.override for programs.mpv.
          mpv = dgpuAppend final prev.mpv { bins = [ "mpv" ]; nodeArg = "--vaapi-device="; };
          retroarch =
            let wrap = r: dgpuAppend final r { bins = [ "retroarch" ]; } // { withCores = f: wrap (r.withCores f); };
            in wrap prev.retroarch;
        })
      ];
    };

  # Elgato cards drop frames suspended.
  capture = {
    services.udev.extraRules = ''
      SUBSYSTEM=="usb", ATTR{idVendor}=="0fd9", TEST=="power/control", ATTR{power/control}="on"
    '';
    environment.systemPackages = [ pkgs.v4l-utils ];
  };

  # Daemon starts when a tablet appears.
  tablets =
    let
      vendorIds = [
        "056a"
        "256c"
        "28bd"
        "2feb"
        "172f"
      ];

      rule = vid: ''
        SUBSYSTEM=="usb", ATTR{idVendor}=="${vid}", TAG+="systemd", ENV{SYSTEMD_USER_WANTS}+="opentabletdriver.service"
        SUBSYSTEM=="hidraw", ATTRS{idVendor}=="${vid}", TAG+="systemd", ENV{SYSTEMD_USER_WANTS}+="opentabletdriver.service"
      '';
    in
    {
      hardware.opentabletdriver = {
        enable = true;
        daemon.enable = true;
        blacklistedKernelModules = [ "hid-uclogic" "wacom" ];
      };

      systemd.user.services.opentabletdriver.wantedBy = lib.mkForce [ ];

      services.udev.extraRules = lib.concatStringsSep "\n" (map rule vendorIds);
    };
in
{
  imports = [
    gpuSelect
    offload
    tablets
    capture
    machine
    cpus.${hwData.selection.cpu}
  ]
  ++ map (name: gpus.${renamedGpus.${name} or name}) hwData.selection.gpus
  ++ lib.optional (hwData.platform.arch == "aarch64") soc
  ++ lib.optional ((hwData.platform.virt or "none") != "none") guests.${hwData.platform.virt}
  ++ [ inputs.nixos-hardware.nixosModules.common-pc ];
}
$nix$)
ON CONFLICT (slug) DO NOTHING;
-- +goose StatementEnd

UPDATE modules SET position = 100 + id WHERE position IS NULL;
ALTER TABLE modules ALTER COLUMN position SET NOT NULL;
CREATE INDEX modules_order ON modules (position);

INSERT INTO module_revisions (module_id, revision, source)
SELECT id, revision, source FROM modules ON CONFLICT DO NOTHING;

-- Old registry names to their new home.
INSERT INTO profile_modules (profile_id, module_id)
SELECT DISTINCT p.id, m.id
FROM profiles p
    CROSS JOIN LATERAL unnest(p.catalog) AS c(name)
    JOIN (VALUES
        ('gaming', 'gaming'), ('boost', 'gaming'), ('gametune', 'gaming'), ('prewarm', 'gaming'),
        ('rom-playlists', 'gaming'), ('dcspit', 'gaming'), ('dns-ecs', 'gaming'), ('home-emulators', 'gaming'),
        ('packages', 'apps'), ('brave', 'apps'), ('newsboat', 'apps'), ('w3m', 'apps'), ('viewers', 'apps'),
        ('mpv', 'apps'), ('citrix', 'apps'), ('claude-thumbs', 'apps'), ('home-claude', 'apps'),
        ('home-caveman', 'apps'), ('home-meshy', 'apps'), ('home-blender', 'apps'),
        ('calculator', 'desktop'), ('freecad', 'desktop'), ('gaea', 'desktop'), ('retroarch', 'desktop'),
        ('htpc-%', 'htpc'))
        AS moved(pattern, slug) ON c.name LIKE moved.pattern
    JOIN modules m ON m.slug = moved.slug
ON CONFLICT DO NOTHING;

-- Fresh installs start with the three profiles.
INSERT INTO profiles (name, title, platform, description)
SELECT * FROM (VALUES
    ('desktop', 'Desktop', 'desktop'::platform, 'Stasjonære arbeidsmaskiner'),
    ('laptop', 'Laptop', 'desktop'::platform, 'Bærbare maskiner med samme oppsett som desktop'),
    ('htpc', 'HTPC', 'htpc'::platform, 'Stueboks med Steam, GeForce NOW og media')) AS seed
WHERE NOT EXISTS (SELECT 1 FROM profiles);

INSERT INTO profile_modules (profile_id, module_id)
SELECT p.id, m.id
FROM profiles p
    JOIN (VALUES
        ('desktop', 'gaming'), ('desktop', 'apps'), ('desktop', 'desktop'),
        ('laptop', 'gaming'), ('laptop', 'apps'), ('laptop', 'desktop'),
        ('htpc', 'gaming'), ('htpc', 'apps'), ('htpc', 'htpc')) AS seed(profile, slug) ON seed.profile = p.name
    JOIN modules m ON m.slug = seed.slug
WHERE NOT EXISTS (SELECT 1 FROM profile_modules pm WHERE pm.profile_id = p.id)
ON CONFLICT DO NOTHING;

ALTER TABLE profiles DROP COLUMN catalog;
DROP TABLE catalog_modules;
DROP TABLE catalog_categories;

-- +goose Down
CREATE TABLE catalog_categories (
    name text PRIMARY KEY,
    title text NOT NULL,
    position integer NOT NULL
);

CREATE TABLE catalog_modules (
    name text PRIMARY KEY,
    category text NOT NULL,
    position integer NOT NULL,
    title text NOT NULL,
    path text NOT NULL,
    x86_only boolean NOT NULL DEFAULT false,
    required boolean NOT NULL DEFAULT false,
    automatic boolean NOT NULL DEFAULT false,
    defaults text[] NOT NULL DEFAULT '{}',
    present boolean NOT NULL DEFAULT true
);

CREATE INDEX catalog_modules_order ON catalog_modules (category, position);

ALTER TABLE profiles ADD COLUMN catalog text[] NOT NULL DEFAULT '{}';

DELETE FROM profile_modules WHERE module_id IN (SELECT id FROM modules WHERE position <= 11);
DELETE FROM modules WHERE position <= 11;
DROP INDEX modules_order;
ALTER TABLE modules DROP COLUMN position, DROP COLUMN required;
