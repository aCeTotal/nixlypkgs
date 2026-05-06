{
  description = "nixlypkgs – lightweight nixpkgs-style overlay repo";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    # Tracked as raw source — the derivation in pkgs/nixly_launcher consumes
    # it as `src`. Swap to fetchFromGitHub when the project is published.
    nixly_launcher_src = {
      url = "path:/home/total/nixly_launcher";
      flake = false;
    };
    nixly_lockscreen_src = {
      url = "path:/home/total/nixly_lockscreen";
      flake = false;
    };
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
      lib = nixpkgs.lib;

      overlays.default = import ./overlays/default.nix inputs;

      legacyPackages = forAllSystems mkPkgs;

      packages = forAllSystems (system:
        let
          pkgs = self.legacyPackages.${system};
        in {
          inherit (pkgs) winstripping speedtree nixlytile nixly_launcher nixly_lockscreen nixlymediaserver;

          dwl = pkgs.nixlytile;
          default = pkgs.nixlytile;
        });

      # Drop-in modules to enable the overlay system-wide or per-user
      nixosModules = {
        nixlypkgs = { ... }: {
          nixpkgs.overlays = [ self.overlays.default ];
        };
        nixlymediaserver = import ./modules/nixlymediaserver.nix;
        nixly_lockscreen = import ./modules/nixly_lockscreen.nix;
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
