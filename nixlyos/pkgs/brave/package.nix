# Vendored: nixpkgs dropped brave.
{ stdenv, callPackage, ... }@args:

let
  pname = "brave";
  version = "1.99.55";

  archives = {
    x86_64-linux = {
      url = "https://github.com/brave/brave-browser/releases/download/v${version}/brave-browser_${version}_amd64.deb";
      hash = "sha256-Nk6VSirYTVuj4OIXoinVhzxK5xB9FeYSDkIHUpU5yI0=";
    };
    aarch64-linux = {
      url = "https://github.com/brave/brave-browser/releases/download/v${version}/brave-browser_${version}_arm64.deb";
      hash = "sha256-r5nwaDDQllA/Zmezb/btbEVf7vUgPw0o/vTP065e4Qo=";
    };
  };
in
callPackage ./make-brave.nix (removeAttrs args [ "callPackage" ]) (
  archives.${stdenv.hostPlatform.system} // { inherit pname version; }
)
