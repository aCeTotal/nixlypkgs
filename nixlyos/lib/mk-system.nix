# Builds a complete NixlyOS system from per-machine data. Everything that is
# the same on every machine lives in this repo; everything per-machine comes
# from hardwareDir (written by nixlyos-detect-hw into ~/.local/nixlyos):
#
#   hardware-configuration.nix   nixos-generate-config output
#   selection.nix                { cpu = "intel"; gpus = [ "nvidia_intel" ... ]; }
#   detected.nix                 PCI bus ids + NVIDIA arch/branch
#   resources.nix                cores/RAM/psABI level/build parallelism
#   dmi.nix                      vendor/model/laptop flag
#   profile.nix                  nixos-hardware module names + flags
#   devices.nix                  module gating services on present devices
{ self, inputs }:

{ system ? "x86_64-linux"
, hostName
, stateVersion
, hardwareDir
, localConfig ? null
  # User extension point (~/.local/nixlyos/custom): modules.nix is a normal
  # NixOS module, guarded so it cannot touch core-owned options; userInputs
  # carries the resolved extra flake inputs declared in custom/inputs.nix.
, userModules ? null
, userInputs ? { }
, username
}:

let
  nixpkgs = inputs.nixos-stable;

  permittedInsecure = [
    "freeimage-unstable-2021-11-01"
    "electron-29.4.6"
    "dotnet-sdk-6.0.428"
    "dotnet-runtime-6.0.36"
    "dotnet-sdk-wrapped-6.0.428"
    "libxml2-2.13.8"
    "libsoup-2.74.3"
  ];

  pkgs = import nixpkgs {
    inherit system;
    config = {
      allowUnfree = true;
      permittedInsecurePackages = permittedInsecure;
      # The old NVIDIA branches need explicit license acceptance on top of
      # allowUnfree, or eval fails on Kepler and older machines.
      nvidia.acceptLicense = true;
    };
    overlays = [
      self.overlays.default
      (import ../pkgs/chrome/overlay.nix)
    ];
  };

  pkgsUnstable = import inputs.nixpkgs {
    inherit system;
    config = {
      allowUnfree = true;
      permittedInsecurePackages = permittedInsecure;
    };
  };

  totalvimSrc = inputs.totalvim;
  totalvimVimPlugin = pkgs.callPackage (totalvimSrc + "/plugins/totalvim") { };
  totalvimPkg = inputs.mnw.lib.wrap {
    inherit pkgs;
    inputs = {
      self.legacyPackages.${system}.vimPlugins.totalvim = totalvimVimPlugin;
    };
  } (totalvimSrc + "/nix/mnw");

  hwData = {
    detected = import (hardwareDir + "/detected.nix");
    resources = import (hardwareDir + "/resources.nix");
    dmi = import (hardwareDir + "/dmi.nix");
    profile = import (hardwareDir + "/profile.nix");
  };

  selection = import (hardwareDir + "/selection.nix");
  cpuModule = ../hardware/cpu + "/${selection.cpu}.nix";
  gpuModules = map (n: ../hardware/gpu + "/${n}.nix") selection.gpus;

  # The inputs attrset modules see, under the names they already use.
  moduleInputs = {
    inherit (inputs) lanzaboote nixos-hardware totalvim mnw;
    nixpkgs = inputs.nixos-stable;
    nixpkgs-unstable = inputs.nixpkgs;
    nixlypkgs = self;
  };

  specialArgs = {
    # User inputs merge in under their own names; on a name clash the system
    # inputs win, so nothing in the core can be shadowed from custom/inputs.nix.
    inputs = userInputs // moduleInputs;
    inherit system totalvimPkg hwData;
    pkgs-unstable = pkgsUnstable;
    nixlyUser = username;
  };
in
nixpkgs.lib.nixosSystem {
  inherit system specialArgs;

  modules = [
    ({ ... }: { nixpkgs.pkgs = pkgs; })

    {
      networking.hostName = hostName;
      system.stateVersion = stateVersion;
    }

    (hardwareDir + "/hardware-configuration.nix")
    (hardwareDir + "/devices.nix")

    ../base/default.nix
    cpuModule
  ]
  ++ gpuModules
  ++ [
    inputs.nixos-hardware.nixosModules.common-pc
    self.nixosModules.nixlypkgs
    inputs.lanzaboote.nixosModules.lanzaboote
    inputs.home-manager.nixosModules.home-manager
    {
      home-manager = {
        useGlobalPkgs = true;
        useUserPackages = true;
        backupCommand = ''mv --force "$1" "$1.backup"'';
        extraSpecialArgs = specialArgs;
        users.${username} = import ../home;
      };
    }
  ]
  ++ nixpkgs.lib.optional (localConfig != null) localConfig
  # Guarded by the protected-namespace scan in user-config.sh; an eval-time
  # guard is impossible without forcing otherwise-dead option definitions.
  ++ nixpkgs.lib.optional (userModules != null) userModules;
}
