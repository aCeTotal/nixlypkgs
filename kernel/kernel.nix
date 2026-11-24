# Én kernel: clang thin-LTO, config, bygg.
{
  pkgs,
  nixpkgs,
  lib,
  src,
  version,
  name,
  localVersion,
  patches,
  vendorDrivers,
  caCert,
  baseConfig,
  tweaks,
  checks,
  absent ? [ ],
  # Byggvalg panelet har endret.
  settings ? { },
}@args:
let
  llvmPackages = pkgs.llvmPackages_latest;
  stdenv = llvmPackages.stdenv;

  knobs = (import ./settings.nix { inherit lib; }).knobs;
  chosen = lib.mapAttrsToList (knob: value: knobs.${knob}.options.${value}) settings;
  # Sjekker valgene erstatter.
  owned = lib.concatMap (knob: knobs.${knob}.owns) (lib.attrNames settings);
  kept = lib.filter (entry: !lib.elem (lib.head (lib.splitString "=" entry)) owned);

  # Wrappede binutils brekker thin-LTO.
  llvmFlags = [
    "LD=${lib.getExe' llvmPackages.lld "ld.lld"}"
    "AR=${lib.getExe' llvmPackages.llvm "llvm-ar"}"
    "NM=${lib.getExe' llvmPackages.llvm "llvm-nm"}"
  ];

  commonMakeFlags = import "${nixpkgs}/pkgs/os-specific/linux/kernel/common-flags.nix" {
    inherit lib stdenv;
    inherit (pkgs) buildPackages;
    extraMakeFlags = llvmFlags;
  };

  configfile = pkgs.callPackage ./configfile.nix {
    inherit
      stdenv
      src
      baseConfig
      commonMakeFlags
      patches
      vendorDrivers
      ;
    absent = kept absent;
    kernelVersion = version;
    tweaks = lib.concatStringsSep " " (
      tweaks
      ++ lib.concatMap (option: option.tweaks) chosen
      ++ import ./tweaks/security.nix caCert
      ++ [
        "--set-str LOCALVERSION ${localVersion}"
        "-d LOCALVERSION_AUTO"
      ]
    );
    checks = kept checks ++ lib.concatMap (option: option.checks) chosen ++ [
      "SECURITYFS=y"
      "MODULE_SIG_FORCE=y"
      "LOCK_DOWN_KERNEL_FORCE_CONFIDENTIALITY=y"
      "HIBERNATION=y"
    ];
  };
in
(pkgs.linuxManualConfig {
  inherit
    version
    src
    stdenv
    configfile
    ;
  modDirVersion = lib.versions.pad 3 "${version}${localVersion}";
  allowImportFromDerivation = true;
  extraMakeFlags = llvmFlags;
  kernelPatches = map (p: {
    name = builtins.baseNameOf p;
    patch = p;
  }) patches;
  features = {
    efiBootStub = true;
    ia32Emulation = true;
  };
}).overrideAttrs
  (prev: {
    pname = name;
    postPatch = (prev.postPatch or "") + vendorDrivers;
    passthru = prev.passthru // {
      inherit configfile caCert;
      tune = more: import ./kernel.nix (args // { settings = settings // more; });
    };
  })
