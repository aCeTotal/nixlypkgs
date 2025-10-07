{
  description = "nixlypkgs – lightweight nixpkgs-style overlay repo";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" "x86_64-darwin" ];
      forAllSystems = f: builtins.listToAttrs (map (system: {
        name = system;
        value = f system;
      }) systems);

      overlay = import ./overlays/default.nix;
    in {
      overlays.default = overlay;

      packages = forAllSystems (system:
        let pkgs = import nixpkgs { inherit system; overlays = [ overlay ]; };
        in {
          inherit (pkgs) nixly-hello winboat winintegration winstripping;
          default = pkgs.nixly-hello;
        }
      );

      devShells = forAllSystems (system:
        let pkgs = import nixpkgs { inherit system; overlays = [ overlay ]; };
        in {
          default = pkgs.mkShell {
            packages = with pkgs; [ nixpkgs-fmt ];
          };
        }
      );

      formatter = forAllSystems (system:
        let pkgs = import nixpkgs { inherit system; overlays = [ overlay ]; };
        in pkgs.nixpkgs-fmt);
    };
}
