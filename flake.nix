{
  description = "nixlypkgs – lightweight nixpkgs-style overlay repo";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixly_launcher_src = {
      url = "github:aCeTotal/nixly_launcher";
      flake = false;
    };
    codeindexcache_src = {
      url = "github:aCeTotal/codeindexcache";
      flake = false;
    };
    nixly_voice_src = {
      url = "github:aCeTotal/nixly_voice";
      flake = false;
    };

    # This lock is the system pin.
    nixos-stable.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    home-manager.url = "github:nix-community/home-manager/release-26.05";
    lanzaboote.url = "github:nix-community/lanzaboote";
    totalvim = {
      url = "github:aCeTotal/totalvim";
      flake = false;
    };
    mnw.url = "github:Gerg-L/mnw";
    # Parallel evaluator for nixlyos-update.
    determinate-nix = {
      url = "github:DeterminateSystems/nix-src/v3.24.2";
      inputs.nixpkgs.follows = "nixos-stable";
    };

    # NixlyOS gaming kernel.
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

      # Mirrors mk-system's instance for cache hits.
      stableFor = system: import inputs.nixos-stable {
        inherit system;
        config = import ./nixlyos/lib/pkgs-config.nix;
        overlays = [
          self.overlays.default
          (import ./nixlyos/pkgs/brave/overlay.nix)
          (import ./nixlyos/scripts/overlay.nix)
        ];
      };
    in {
      lib = nixpkgs.lib // {
        mkNixlySystem = import ./nixlyos/lib/mk-system.nix { inherit self inputs; };
        mkNixlyServer = import ./nixlyserver/mk-server.nix { inherit self inputs; };
        nixlyos = {
          # Caches every machine trusts.
          caches = import ./nixlyos/lib/caches.nix;
          # Package set the panel builds against.
          pkgs = stableFor;
          # nixpkgs below it, without nixlypkgs.
          nixpkgs = system: inputs.nixos-stable.legacyPackages.${system};
          # Single-output package-set attrs only.
          pinnable = system:
            let stable = stableFor system; in
            builtins.filter (name: stable ? ${name} && (stable.${name}.outputs or [ "out" ]) == [ "out" ])
              (builtins.attrNames self.packages.${system});
        };
      };

      overlays.default = import ./overlays/default.nix inputs;

      legacyPackages = forAllSystems mkPkgs;

      # The panel caches every attr.
      packages = forAllSystems (system:
        let
          stable = stableFor system;
          # Out-of-tree modules per nixlyos kernel.
          kernelModules = suffix: kp:
            nixpkgs.lib.mapAttrs'
              (name: nixpkgs.lib.nameValuePair "${name}-nixlyos${suffix}")
              {
                nvidia-modules = kp.nvidiaPackages.latest.mod;
                nvidia-modules-previous = kp.nvidiaPackages.previous.mod;
              };
        in {
          inherit (stable) speedtree nixlytile nixlycc nixly_launcher nixly_lockscreen nixlymediaserver nixlymedia Blender_bin_lts Unreal_editor gaea low-latency-layer nixly-vrs proton-nixlyos proton-nixlyos-generic flycast claude citrix-workspace-nixly nixly-mic nixly-gate nixly_kalk nixly_pdf nixly_voice meshy freecad-mcp codeindexcache determinate-nix nixlyos-panel;

          # Layer for 32-bit games.
          nixly-vrs-i686 = stable.pkgsi686Linux.nixly-vrs;

          totalvim = import ./nixlyos/lib/totalvim.nix {
            pkgs = stable;
            inherit system inputs;
          };

          inherit (stable) linux-nixlyserver;
          linux-nixlyserver-modules = stable.linux-nixlyserver.modules;
          linux-nixlyserver-dev = stable.linux-nixlyserver.dev;

          # Unfree, never on cache.nixos.org.
          nvidia-nixlyos = stable.linuxPackages_nixlyos.nvidiaPackages.latest;
          nvidia-nixlyos-persistenced = stable.linuxPackages_nixlyos.nvidiaPackages.latest.persistenced;
          # Cached fallback driver.
          nvidia-nixlyos-previous = stable.linuxPackages_nixlyos.nvidiaPackages.previous;
          nvidia-nixlyos-previous-persistenced = stable.linuxPackages_nixlyos.nvidiaPackages.previous.persistenced;

          cachepanel = stable.callPackage ./cachepanel/nix/package.nix { };

          dwl = stable.nixlytile;
          default = stable.nixlytile;
        }
        // kernelModules "" stable.linuxPackages_nixlyos
        // kernelModules "-v3" stable.linuxPackages_nixlyos_v3
        // kernelModules "-v4" stable.linuxPackages_nixlyos_v4
        # Every output of the nixlyos kernels.
        // nixpkgs.lib.concatMapAttrs (name: kernel: { ${name} = kernel; "${name}-modules" = kernel.modules; "${name}-dev" = kernel.dev; })
          { inherit (stable) linux-nixlyos linux-nixlyos-v3 linux-nixlyos-v4 linux-nixlyos-enterprise; }
        // nixpkgs.lib.genAttrs (import ./pkgs/recipes.nix) (name: stable.${name}));

      nixosModules = {
        nixlypkgs = { ... }: {
          nixpkgs.overlays = [ self.overlays.default ];
        };
        nixlymediaserver = import ./modules/nixlymediaserver.nix;
        nixly_lockscreen = import ./modules/nixly_lockscreen.nix;
        citrix-workspace = import ./modules/citrix-workspace.nix;
        codeindexcache = import ./modules/codeindexcache.nix inputs;
        cachepanel = { lib, pkgs, ... }: {
          imports = [ ./cachepanel/nix/module.nix ];
          services.nixly-cachepanel.package = lib.mkDefault self.packages.${pkgs.stdenv.hostPlatform.system}.cachepanel;
        };
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
