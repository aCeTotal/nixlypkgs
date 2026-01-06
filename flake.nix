{
  description = "nixlypkgs – lightweight nixpkgs-style overlay repo";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

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
        let pkgs = self.legacyPackages.${system};
        in {
          inherit (pkgs) nixly-hello winstripping speedtree nixlytile;
          default = pkgs.nixly-hello;
        });

      # Drop-in modules to enable the overlay system-wide or per-user
      nixosModules = {
        nixlypkgs = { ... }: {
          nixpkgs.overlays = [ self.overlays.default ];
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
