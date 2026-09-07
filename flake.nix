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
    lanzaboote.url = "github:nix-community/lanzaboote";
    totalvim = {
      url = "github:aCeTotal/totalvim";
      flake = false;
    };
    mnw.url = "github:Gerg-L/mnw";

    # NixlyOS gaming-kernel (CachyOS-saus + BORE + scx_lavd, generic + v3).
    # `nix flake update nixlyos-kernel` etter push til kernel-repoet.
    nixlyos-kernel.url = "github:aCeTotal/kernel_nixlyos";
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

      # The nixlycaching watcher on the cache server builds every attr in
      # packages.x86_64-linux on each main commit; whatever is listed here is
      # what machines get from cache.aceclan.no instead of building locally.
      packages = forAllSystems (system:
        let
          # Machines build everything through mk-system's nixos-stable
          # instance. Cache entries only help if they are those exact
          # derivations, so this mirrors that instance (same nixpkgs,
          # config and overlays) - built from unstable legacyPackages the
          # store paths would never match a machine eval.
          stable = import inputs.nixos-stable {
            inherit system;
            config = import ./nixlyos/lib/pkgs-config.nix;
            overlays = [
              self.overlays.default
              (import ./nixlyos/pkgs/chrome/overlay.nix)
            ];
          };
          # Every out-of-tree module machines compile against a nixlyos
          # kernel (nvidia's `.mod` is what boot.extraModulePackages builds;
          # the rest come from apps/gaming.nix and hardware/msi-ec.nix).
          kernelModules = suffix: kp:
            nixpkgs.lib.mapAttrs'
              (name: nixpkgs.lib.nameValuePair "${name}-nixlyos${suffix}")
              {
                nvidia-modules = kp.nvidiaPackages.latest.mod;
                inherit (kp) xpadneo xone xpad-noone msi-ec;
              };
        in {
          inherit (stable) speedtree nixlytile nixlycc nixly_launcher nixly_lockscreen nixlymediaserver nixlymedia geforce-now Blender_bin_lts Unreal_editor gaea low-latency-layer proton-nixlyos proton-nixlyos-generic linux-nixlyos linux-nixlyos-v3 flycast claude citrix-workspace-nixly;

          totalvim = import ./nixlyos/lib/totalvim.nix {
            pkgs = stable;
            inherit system inputs;
          };

          # Kernel-independent nvidia userspace parts (unfree, so never on
          # cache.nixos.org): the driver itself and persistenced.
          nvidia-nixlyos = stable.linuxPackages_nixlyos.nvidiaPackages.latest;
          nvidia-nixlyos-persistenced = stable.linuxPackages_nixlyos.nvidiaPackages.latest.persistenced;

          dwl = stable.nixlytile;
          default = stable.nixlytile;
        }
        // kernelModules "" stable.linuxPackages_nixlyos
        // kernelModules "-v3" stable.linuxPackages_nixlyos_v3);

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
