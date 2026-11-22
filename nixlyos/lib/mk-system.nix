# Machine data to NixlyOS system.
{ self, inputs }:

{ system ? null
, hostName
, stateVersion
, hardwareDir
, localConfig ? null
  # Guarded user extension point.
, userModules ? null
, userInputs ? { }
, username
  # Panel-published profile tree.
, profileTree ? null
}:

let
  nixpkgs = inputs.nixos-stable;

  # Undetected machines: x86 EFI.
  platform =
    if builtins.pathExists (hardwareDir + "/platform.nix")
    then import (hardwareDir + "/platform.nix")
    else { arch = "x86_64"; soc = null; bootMode = "efi"; bootDevice = null; virt = "none"; };

  effectiveSystem =
    if system != null then system
    else if platform.arch == "aarch64" then "aarch64-linux"
    else "x86_64-linux";

  # Shared with the cached packages.
  pkgsConfig = import ./pkgs-config.nix;

  pkgs = import nixpkgs {
    system = effectiveSystem;
    config = pkgsConfig;
    overlays = [
      self.overlays.default
      (import ../pkgs/brave/overlay.nix)
      (import ../pkgs/polkit-gnome/overlay.nix)
    ];
  };

  pkgsUnstable = import inputs.nixpkgs {
    system = effectiveSystem;
    config = pkgsConfig;
  };

  # Same file as packages.totalvim.
  totalvimPkg = import ./totalvim.nix { inherit pkgs inputs; system = effectiveSystem; };

  detected = import (hardwareDir + "/detected.nix");

  hwData = {
    # Laptop panels sit on the iGPU.
    detected = {
      primary = nixpkgs.lib.findFirst (v: detected.${v} != "") "intel"
        (if hwData.dmi.isLaptop then [ "intel" "amd" "nvidia" ] else [ "intel" "nvidia" "amd" ]);
    } // detected;
    resources = import (hardwareDir + "/resources.nix");
    dmi = import (hardwareDir + "/dmi.nix");
    profile = import (hardwareDir + "/profile.nix");
    inherit platform;
  };

  selection = import (hardwareDir + "/selection.nix");
  cpuModule = ../hardware/cpu + "/${selection.cpu}.nix";
  # Older detect-hw names.
  renamedGpus = { nvidia_intel = "nvidia_hybrid"; };
  gpuModules = map (n: ../hardware/gpu + "/${renamedGpus.${n} or n}.nix") selection.gpus;

  # Boards come from nixos-hardware candidates.
  socModules = nixpkgs.lib.optional (platform.arch == "aarch64") ../hardware/soc/arm.nix;
  virtModules = nixpkgs.lib.optional ((platform.virt or "none") != "none")
    (../hardware/virt + "/${platform.virt}.nix");

  # Inputs under their familiar names.
  moduleInputs = {
    inherit (inputs) lanzaboote nixos-hardware totalvim mnw;
    nixpkgs = inputs.nixos-stable;
    nixpkgs-unstable = inputs.nixpkgs;
    nixlypkgs = self;
  };

  profileData = if profileTree == null then null else builtins.fromJSON (builtins.readFile (profileTree + "/profile.json"));

  # Local pins win over profile pins.
  pinsFiles = nixpkgs.lib.optional (profileTree != null) (profileTree + "/pins.nix") ++ [ (dirOf hardwareDir + "/pins.nix") ];

  specialArgs = {
    # System inputs win name clashes.
    inputs = userInputs // moduleInputs;
    inherit totalvimPkg hwData;
    system = effectiveSystem;
    pkgs-unstable = pkgsUnstable;
    nixlyUser = username;
    nixlySelection = if profileData == null then null else profileData.modules;
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
    (import ./pins.nix pinsFiles)
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
  ++ nixpkgs.lib.optional (profileTree != null) (profileTree + "/default.nix")
  ++ nixpkgs.lib.optional (localConfig != null) localConfig
  # Guarded by user-config.sh's scan.
  ++ nixpkgs.lib.optional (userModules != null) userModules;
}
