# Machine data to NixlyServer system.
{ self, inputs }:

{ hostName
, stateVersion
, hardwareDir
, username
, sshKeys
  # BIOS grub disk; null: UEFI.
, biosBootDevice ? null
, localConfig ? null
}:

let
  nixpkgs = inputs.nixos-stable;
in
nixpkgs.lib.nixosSystem {
  system = "x86_64-linux";

  specialArgs = {
    nixlyUser = username;
    inherit sshKeys biosBootDevice;
  };

  modules = [
    {
      nixpkgs.overlays = [ self.overlays.default ];
      networking.hostName = hostName;
      system.stateVersion = stateVersion;
    }
    (hardwareDir + "/hardware-configuration.nix")
    inputs.lanzaboote.nixosModules.lanzaboote
    ./default.nix
  ]
  ++ nixpkgs.lib.optional (localConfig != null) localConfig;
}
