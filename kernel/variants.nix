# Desktop, server og enterprise.
{
  pkgs,
  nixpkgs,
  linux-src,
  linux-vanilla,
  cachy-config,
  cachy-patches,
  drivers,
  caCert,
}:
let
  inherit (pkgs) lib;
  srcVersion = import ./version.nix {
    inherit lib;
    src = linux-src;
  };
  stable = import ./stable.nix;
  # Siste stabilpatch gir versjonen.
  sublevel = patch: lib.last (lib.splitString "-" (lib.removeSuffix ".xz" (baseNameOf patch.url)));
  version =
    if stable.patches == [ ] then
      srcVersion
    else
      "${lib.versions.majorMinor srcVersion}.${sublevel (lib.last stable.patches)}";
  march = import ./tweaks/march.nix;
  vanillaVersion = import ./version.nix {
    inherit lib;
    src = linux-vanilla;
  };

  # Kjeden uten filer CachyOS endret.
  stablePatch = pkgs.runCommand "linux-stable-${version}.patch" { nativeBuildInputs = [ pkgs.patchutils ]; } ''
    xzcat ${lib.concatMapStringsSep " " pkgs.fetchurl stable.patches} \
      | filterdiff -p1 ${lib.concatMapStringsSep " " (f: "-x ${f}") stable.conflicts} > $out
  '';

  performance =
    {
      name,
      localVersion,
      march,
    }:
    import ./kernel.nix {
      inherit
        pkgs
        nixpkgs
        lib
        version
        name
        localVersion
        caCert
        ;
      src = linux-src;
      patches =
        lib.optionals (stable.patches != [ ]) [
          stablePatch
          ./stable-fixup.patch
        ]
        ++ [
          "${cachy-patches}/${lib.versions.majorMinor version}/sched/0001-bore-cachy.patch"
          ./patches/xone.patch
          ./patches/xpadneo.patch
          ./patches/secure-hibernation.patch
        ];
      vendorDrivers = import ./drivers.nix drivers;
      baseConfig = "cp ${cachy-config}/linux-cachyos/config .config";
      tweaks =
        import ./tweaks/base.nix
        ++ import ./tweaks/timing.nix
        ++ import ./tweaks/perf.nix
        ++ import ./tweaks/devices.nix
        ++ march.flags;
      checks = [
        "SCHED_BORE=y"
        "SCHED_CLASS_EXT=y"
        "HZ=1000"
        "NO_HZ_FULL=y"
        "PREEMPT=y"
        "CC_OPTIMIZE_FOR_PERFORMANCE_O3=y"
        "TRANSPARENT_HUGEPAGE_ALWAYS=y"
        "LTO_CLANG_THIN=y"
        "DEFAULT_TCP_CONG=.bbr3."
        "NTSYNC=y"
        "JOYSTICK_XONE=m"
        "HID_XPADNEO=m"
        "MSI_EC=m"
        march.check
      ];
    };
in
{
  generic = performance {
    name = "linux-nixlyos";
    localVersion = "-nixlyos";
    march = march.generic;
  };
  v3 = performance {
    name = "linux-nixlyos-v3";
    localVersion = "-nixlyos-v3";
    march = march.v3;
  };
  enterprise = import ./kernel.nix {
    inherit pkgs nixpkgs lib caCert;
    src = linux-vanilla;
    version = vanillaVersion;
    name = "linux-nixlyos-enterprise";
    localVersion = "-nixlyos-enterprise";
    patches = [ ./patches/secure-hibernation.patch ];
    vendorDrivers = "";
    baseConfig = "make $makeFlags defconfig hardening.config";
    tweaks = import ./tweaks/hardening.nix ++ import ./enterprise/desktop.nix ++ import ./enterprise/hardware.nix;
    checks = [
      "CFI=y"
      "INIT_ON_FREE_DEFAULT_ON=y"
      "IOMMU_DEFAULT_DMA_STRICT=y"
      "BPF_UNPRIV_DEFAULT_OFF=y"
      "ZERO_CALL_USED_REGS=y"
      "LTO_CLANG_THIN=y"
      "HZ=1000"
      "PREEMPT=y"
      "DEFAULT_TCP_CONG=.bbr."
      "LSM=.landlock,lockdown,yama."
      "WIREGUARD=y"
      "DM_CRYPT=y"
      "DRM_I915=m"
      "DRM_AMDGPU=m"
      "IWLMVM=m"
      "SND_SOC_SOF_METEORLAKE=m"
      "HID_MICROSOFT=m"
      "HID_APPLE=m"
      "SATA_NV=m"
      "VMD=m"
      "CRYPTO_AES_NI_INTEL=y"
    ];
    absent = [
      "KEXEC"
      "KEXEC_FILE"
      "DEVMEM"
      "IO_URING"
      "PROC_KCORE"
      "MODIFY_LDT_SYSCALL"
      "X86_IOPL_IOPERM"
      "LEGACY_TIOCSTI"
      "DEBUG_FS"
      "FTRACE"
      "SECURITY_SELINUX"
    ];
  };

  # Vanilla og herdet, med full maskinvaredekning.
  server = import ./kernel.nix {
    inherit pkgs nixpkgs lib caCert;
    src = linux-vanilla;
    version = vanillaVersion;
    name = "linux-nixlyos-server";
    localVersion = "-nixlyos-server";
    patches = [ ./patches/secure-hibernation.patch ];
    vendorDrivers = "";
    baseConfig = "cp ${cachy-config}/linux-cachyos/config .config && make $makeFlags olddefconfig hardening.config";
    tweaks = import ./tweaks/hardening.nix ++ import ./tweaks/server.nix;
    checks = [
      "INIT_ON_FREE_DEFAULT_ON=y"
      "IOMMU_DEFAULT_DMA_STRICT=y"
      "BPF_UNPRIV_DEFAULT_OFF=y"
      "LTO_CLANG_THIN=y"
      "HZ=1000"
      "NO_HZ_IDLE=y"
      "PREEMPT_LAZY=y"
      "TRANSPARENT_HUGEPAGE_MADVISE=y"
      "DEFAULT_TCP_CONG=.bbr."
      "DEFAULT_FQ=y"
      "LSM=.landlock,lockdown,yama."
      "KVM=m"
      "NFSD=m"
      "BONDING=m"
      "MD_RAID456=m"
      "BINFMT_MISC=y"
    ];
    absent = [
      "KEXEC"
      "KEXEC_FILE"
      "DEVMEM"
      "IO_URING"
      "PROC_KCORE"
      "DEBUG_FS"
      "FTRACE"
      "PREEMPT"
      "CFI"
      "NO_HZ_FULL"
      "TRANSPARENT_HUGEPAGE_ALWAYS"
    ];
  };
}
