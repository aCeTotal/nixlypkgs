{
  description = "Nixly control panel: binary cache, profiles and the package wizard";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      cachepanel = pkgs.callPackage ./nix/package.nix { };
    in
    {
      packages.${system} = {
        inherit cachepanel;
        default = pkgs.callPackage ./nix/stack.nix { inherit cachepanel; };
      };

      nixosModules.default = {
        imports = [ ./nix/module.nix ];
        services.nixly-cachepanel.package = nixpkgs.lib.mkDefault cachepanel;
      };

      checks.${system}.vm = pkgs.testers.runNixOSTest (import ./nix/vm-test.nix {
        module = self.nixosModules.default;
      });

      devShells.${system}.default = pkgs.mkShell {
        packages = with pkgs; [
          go
          gopls
          golangci-lint
          nodejs_24
          postgresql
          process-compose
          nix-eval-jobs
          nixfmt
          git
        ];
        env.CGO_ENABLED = "0";
      };
    };
}
