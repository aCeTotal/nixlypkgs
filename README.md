# nixlypkgs

Et lite overlay-repo for Nix som etterligner struktur i nixpkgs på en lettvekts måte. Denne mappen er ment å bli publisert til GitHub: `aCeTotal/nixlypkgs` og brukes som flake input.

## Innhold
- `pkgs/` – katalog med derivations (en per mappe)
- `overlays/default.nix` – overlay som eksporterer pakkene
- `flake.nix` – eksporterer `packages`, `overlay(s)` og `devShells`

## Bruk som flake input
Legg til i din `flake.nix`:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixlypkgs.url = "github:aCeTotal/nixlypkgs";
  };

  outputs = { self, nixpkgs, nixlypkgs, ... }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" "x86_64-darwin" ];
      forEachSystem = f: builtins.listToAttrs (map (system: {
        name = system;
        value = f system;
      }) systems);
    in {
      packages = forEachSystem (system:
        let pkgs = import nixpkgs { inherit system; overlays = [ nixlypkgs.overlays.default ]; };
        in {
          inherit (pkgs) nixly-hello;
          default = pkgs.nixly-hello;
        }
      );
    };
}
```

Deretter kan du bygge en pakke, for eksempel:

```
nix build .#nixly-hello
```

eller bruke overlayet i dine egne imports.

## Pakker
- `nixly-hello` – enkel eksempelpakke via `writeShellScriptBin`

## Bidra
- Legg nye pakker i `pkgs/<pakkenavn>/default.nix`
- Eksponer pakken i `overlays/default.nix`
- Hold navn i `kebab-case` og bruk `callPackage`-stil (ingen eksplisitte inputs utover attrs).

