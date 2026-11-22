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

assert profileTree != null
  || throw "NixlyOS følger en profil i Nixly-panelet. Kjør: nix run github:aCeTotal/nixlypkgs#nixlyos-panel adopt";

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
      (import ../scripts/overlay.nix)
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
    selection = import (hardwareDir + "/selection.nix");
    inherit platform;
  };

  # Inputs under their familiar names.
  moduleInputs = {
    inherit (inputs) lanzaboote nixos-hardware totalvim mnw;
    nixpkgs = inputs.nixos-stable;
    nixpkgs-unstable = inputs.nixpkgs;
    nixlypkgs = self;
  };

  # Local pins win over profile pins.
  pinsFiles = [ (profileTree + "/pins.nix") (dirOf hardwareDir + "/pins.nix") ];

  specialArgs = {
    # System inputs win name clashes.
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

    (profileTree + "/default.nix")
    (import ./pins.nix pinsFiles)
    inputs.home-manager.nixosModules.home-manager
    {
      home-manager = {
        useGlobalPkgs = true;
        useUserPackages = true;
        backupCommand = ''mv --force "$1" "$1.backup"'';
        extraSpecialArgs = specialArgs;
      };
    }
  ]
  ++ nixpkgs.lib.optional (localConfig != null) localConfig
  # Guarded by user-config.sh's scan.
  ++ nixpkgs.lib.optional (userModules != null) userModules;
}
