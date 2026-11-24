{ config, lib, pkgs, inputs, hwData, ... }:

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

  # In-tree msi-ec matches firmware siblings.
  msiEc = {
    boot.kernelModules = [ "msi-ec" ];

    # The compositor writes these directly.
    services.udev.extraRules = ''
      ACTION=="add|change|bind", SUBSYSTEM=="platform", KERNEL=="msi-ec", RUN+="/bin/sh -c 'cd /sys/devices/platform/msi-ec && chmod 0666 fan_mode shift_mode cooler_boost cpu/fan_curve gpu/fan_curve 2>/dev/null || true'"
    '';

    # pwm and NVML fans.
    systemd.services.nixly-fand = {
      description = "nixlytile fan control helper";
      wantedBy = [ "multi-user.target" ];
      after = [ "systemd-modules-load.service" ];
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
        SystemCallFilter = [ "@system-service" ];
        CapabilityBoundingSet = [ "CAP_DAC_OVERRIDE" "CAP_CHOWN" ];
        # Control socket lives here.
        ReadWritePaths = [ "/run" ];
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
