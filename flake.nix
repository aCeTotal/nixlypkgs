{
  description = "nixlypkgs – lightweight nixpkgs-style overlay repo";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixly_launcher_src = {
      url = "github:aCeTotal/nixly_launcher";
      flake = false;
    };

    # NixlyOS system inputs. This flake.lock is THE system pin: machines only
    # ever run `nix flake update nixlypkgs`, so every rev below ships exactly
    # as tested on the testing branch.
    nixos-stable.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    home-manager.url = "github:nix-community/home-manager/release-26.05";
    # Prebuilt CachyOS kernel + Proton-CachyOS. Never override its nixpkgs
    # input: the nyxpkgs-unstable tag guarantees every store path exists in
    # their cache.
    chaotic.url = "github:chaotic-cx/nyx/nyxpkgs-unstable";
    lanzaboote.url = "github:nix-community/lanzaboote";
    totalvim = {
      url = "github:aCeTotal/totalvim";
      flake = false;
    };
    mnw.url = "github:Gerg-L/mnw";
  };

  outputs = inputs@{ self, nixpkgs, ... }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" "x86_64-darwin" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
      mkPkgs = system: import nixpkgs {
        inherit system;
        overlays = [ self.overlays.default ];
      };
    in {
      lib = nixpkgs.lib // {
        mkNixlySystem = import ./nixlyos/lib/mk-system.nix { inherit self inputs; };
      };

      overlays.default = import ./overlays/default.nix inputs;

      legacyPackages = forAllSystems mkPkgs;

      packages = forAllSystems (system:
        let
          pkgs = self.legacyPackages.${system};
        in {
          inherit (pkgs) speedtree nixlytile nixlycc nixly_launcher nixly_lockscreen nixlymediaserver nixlymedia geforce-now Blender_bin_lts Unreal_editor gaea low-latency-layer proton-nixlyos;

          dwl = pkgs.nixlytile;
          default = pkgs.nixlytile;
        });

      nixosModules = {
        nixlypkgs = { ... }: {
          nixpkgs.overlays = [ self.overlays.default ];
        };
        nixlymediaserver = import ./modules/nixlymediaserver.nix;
        nixly_lockscreen = import ./modules/nixly_lockscreen.nix;
        citrix-workspace = import ./modules/citrix-workspace.nix;
      };

      homeManagerModules = {
        nixlypkgs = { ... }: {
          nixpkgs.overlays = [ self.overlays.default ];
        };
      };

      devShells = forAllSystems (system:
        let pkgs = self.legacyPackages.${system};
        in {
          default = pkgs.mkShell {
            packages = with pkgs; [ nixpkgs-fmt ];
          };
        });

      formatter = forAllSystems (system:
        self.legacyPackages.${system}.nixpkgs-fmt);
    };
}
