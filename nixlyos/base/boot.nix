{ lib, pkgs, hwData, ... }:

{
  boot = {
    loader = {
      efi = {
        canTouchEfiVariables = true;
        efiSysMountPoint = "/boot";
      };

      systemd-boot.enable = true;
      systemd-boot.configurationLimit = 2;
      timeout = 0;
    };

    # lanzaboote = {
    #   enable = true;
    #   pkiBundle = "/var/lib/sbctl";
    #   configurationLimit = 1;
    # };

    initrd.systemd.enable = true;
    # Preload NVMe and btrfs so the root FS comes up without a device wait.
    initrd.availableKernelModules = [ "nvme" "nvme_core" ];
    initrd.kernelModules = [ "btrfs" ];
    consoleLogLevel = 3;
    # tmpfs instead of cleanOnBoot: the on-disk /tmp purge ran inside
    # the initrd ("Create Volatile Files and Directories in the Real
    # Root") and cost ~2 s of every boot.  tmpfs is empty by nature and
    # costs RAM only for what is actually in it; zram+earlyoom handle
    # the pathological cases.
    tmp.useTmpfs = true;

    plymouth.enable = false;

    supportedFilesystems = [ "ext4" "btrfs" "vfat" "ntfs3" ];

    # NixlyOS gaming-kernel from nixlypkgs (kernel_nixlyos flake): CachyOS-saus
    # + BORE + scx_lavd, prebuilt via cache.aceclan.no. v3 build on x86-64-v3
    # CPUs, generic elsewhere. Out-of-tree modules (nvidia, xpadneo, xone,
    # msi-ec) build locally against it; the gpu modules fall back to
    # nvidiaPackages.latest since no prebuilt cachyos driver matches.
    kernelPackages = pkgs.linuxPackagesFor
      (if hwData.resources.cpuLevel >= 3
       then pkgs.linux-nixlyos-v3
       else pkgs.linux-nixlyos);

    kernelParams = [
      "quiet"
      "loglevel=3"
      "rd.udev.log_level=3"
      "udev.log_priority=3"
      "systemd.show_status=false"
      "rd.systemd.show_status=false"
      "8250.nr_uarts=0"
      "transparent_hugepage=always"
      "random.trust_cpu=on"
      "nowatchdog"
      "nmi_watchdog=0"
      # Worth 10-15 % CPU on older Intel; accepted on a single-user desktop.
      "mitigations=off"
      "split_lock_detect=off"
      # Battery target (95 Wh / 10 h ≈ 9.5 W) needs these idle savings:
      # NVMe Autonomous Power State Transition (deep drive sleep after ~100 ms
      # idle) and PCIe Active State Power Management (link L1). Tradeoff: a
      # multi-ms wake stall is possible mid asset-streaming; accepted for the
      # battery budget. Was 0 / performance (gaming-latency biased).
      "nvme_core.default_ps_max_latency_us=100000"
      "pcie_aspm=powersave"
      # auditd is disabled, but the kernel audit path still taxes every
      # syscall until told otherwise.
      "audit=0"
    ];

    blacklistedKernelModules = [ "8250_pci" ];

    # Idle power: HD-audio codec autosuspend (steady idle draw otherwise), and
    # i915 panel self-refresh + framebuffer compression (panel/iGPU savings).
    extraModprobeConfig = ''
      options snd_hda_intel power_save=1 power_save_controller=Y
      options i915 enable_fbc=1 enable_psr=1
    '';
  };

  # sbctl manages the Secure Boot keys.
  environment.systemPackages = [ pkgs.sbctl ];

  security.tpm2 = {
    enable = true;
    pkcs11.enable = true;
    tctiEnvironment.enable = true;
  };

  # No sbctl status check on activation while lanzaboote is disabled.

  boot.kernel.sysctl = {
    "kernel.sysrq" = 1;
    "kernel.kptr_restrict" = 2;
    "kernel.dmesg_restrict" = 1;
    "kernel.unprivileged_bpf_disabled" = 1;
    "fs.protected_hardlinks" = 1;
    "fs.protected_symlinks" = 1;
    "fs.protected_fifos" = 2;
    "fs.protected_regular" = 2;

    # Network hardening
    "net.ipv4.conf.all.rp_filter" = 1;              # reverse path filtering
    "net.ipv4.conf.default.rp_filter" = 1;
    "net.ipv4.conf.all.accept_redirects" = 0;        # reject ICMP redirects
    "net.ipv4.conf.default.accept_redirects" = 0;
    "net.ipv6.conf.all.accept_redirects" = 0;
    "net.ipv6.conf.default.accept_redirects" = 0;
    "net.ipv4.conf.all.send_redirects" = 0;
    "net.ipv4.conf.default.send_redirects" = 0;
    "net.ipv4.conf.all.accept_source_route" = 0;      # block source routing
    "net.ipv6.conf.all.accept_source_route" = 0;
    "net.ipv4.icmp_echo_ignore_broadcasts" = 1;       # smurf attack protection
    # No log_martians: constant journald writes on noisy networks, never read.

    # Anti-exploit hardening
    "kernel.yama.ptrace_scope" = 1;                    # restrict ptrace
    "fs.suid_dumpable" = 0;                            # no core dumps from SUID

    "vm.max_map_count" = 2147483642; # Steam Deck default
  };

  services.fstrim.enable = true;

  # systemd-backlight save/restore costs a second on intel_backlight, and
  # userland sets brightness itself.
  systemd.services."systemd-backlight@backlight:intel_backlight".enable = lib.mkForce false;
}
