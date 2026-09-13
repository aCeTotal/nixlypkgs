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

{ system ? null   # derived from hardware/platform.nix unless passed explicitly
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

  # Platform data (arch/SoC/bootMode/virt) from nixlyos-detect-hw. The
  # fallback keeps machines that have not re-run detection evaluating exactly
  # as before: x86 EFI bare metal.
  platform =
    if builtins.pathExists (hardwareDir + "/platform.nix")
    then import (hardwareDir + "/platform.nix")
    else { arch = "x86_64"; soc = null; bootMode = "efi"; bootDevice = null; virt = "none"; };

  effectiveSystem =
    if system != null then system
    else if platform.arch == "aarch64" then "aarch64-linux"
    else "x86_64-linux";

  # Shared with the flake's packages output (the binary cache builds those
  # attrs) so cache entries are the exact derivations machines evaluate.
  pkgsConfig = import ./pkgs-config.nix;

  pkgs = import nixpkgs {
    system = effectiveSystem;
    config = pkgsConfig;
    overlays = [
      self.overlays.default
      (import ../pkgs/chrome/overlay.nix)
    ];
  };

  pkgsUnstable = import inputs.nixpkgs {
    system = effectiveSystem;
    config = pkgsConfig;
  };

  # Same file as flake packages.totalvim, for the same cache-hit reason.
  totalvimPkg = import ./totalvim.nix { inherit pkgs inputs; system = effectiveSystem; };

  hwData = {
    detected = import (hardwareDir + "/detected.nix");
    resources = import (hardwareDir + "/resources.nix");
    dmi = import (hardwareDir + "/dmi.nix");
    profile = import (hardwareDir + "/profile.nix");
    inherit platform;
  };

  selection = import (hardwareDir + "/selection.nix");
  cpuModule = ../hardware/cpu + "/${selection.cpu}.nix";
  gpuModules = map (n: ../hardware/gpu + "/${n}.nix") selection.gpus;

  # SBCs get the generic ARM SoC module (Mesa graphics); board specifics come
  # from the nixos-hardware candidate matched in profile.nix. Guests get the
  # module for their hypervisor.
  socModules = nixpkgs.lib.optional (platform.arch == "aarch64") ../hardware/soc/arm.nix;
  virtModules = nixpkgs.lib.optional ((platform.virt or "none") != "none")
    (../hardware/virt + "/${platform.virt}.nix");

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
    inherit totalvimPkg hwData;
    system = effectiveSystem;
    pkgs-unstable = pkgsUnstable;
    nixlyUser = username;
  };
in
nixpkgs.lib.nixosSystem {
  system = effectiveSystem;
  inherit specialArgs;

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
  ++ socModules
  ++ virtModules
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
