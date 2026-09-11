# Kernel-packages for nixlyos-kernelen med nvidiaPackages tatt fra nixpkgs
# unstable: nixos-stable henger etter paa driver-versjoner, unstable foelger
# NVIDIAs nyeste. `latest` blir dermed alltid siste driver etter
# `nix flake update nixpkgs`. Modulene bygges fortsatt mot nixlyos-kernelen
# (linuxPackagesFor faar kernel-drv-en inn), saa maskin og cache evaluerer
# identiske store-paths.
inputs: final: kernel:
let
  unstable = import inputs.nixpkgs {
    inherit (final.stdenv.hostPlatform) system;
    # Samme gating som maskin-instansen (allowUnfree + nvidia.acceptLicense).
    config = import ../nixlyos/lib/pkgs-config.nix;
  };
  base = (unstable.linuxPackagesFor kernel).nvidiaPackages;
in
(final.linuxPackagesFor kernel).extend (_: _: {
  # `latest` er alltid nyeste NVIDIA-driver, `previous` alltid den forrige.
  # Begge bygges og caches (flake.nix packages), saa en maskin med problemer
  # kan sette hardware.nvidia.package til nvidiaPackages.previous i
  # custom/modules.nix og faa ferdigbygde binaerer fra cachen.
  #
  # 615.71.09 er nyere enn nixpkgs unstable (610.57.04); pin via mkDriver
  # til unstable tar den igjen, da kan pin-blokken fjernes. Ved bump av
  # latest til ny versjon: flytt gammel pin ned til previous.
  nvidiaPackages = base // {
    latest = base.mkDriver {
      version = "615.71.09";
      sha256_64bit = "sha256-zc7tIrvrYSSNGm3qvCWWZz46ZQFpjucayNL9wo87cP4=";
      sha256_aarch64 = "sha256-AARCH64";
      openSha256 = "sha256-3gByMYIwFzRaLdDG+roCEOuKRRJDrljG9AlLnRZTirM=";
      settingsSha256 = "sha256-LK1LU8mDkM/XVRKPBtuOZh9nIP/lGFLAJnmasEX8jhg=";
      persistencedSha256 = "sha256-qPRb+3d88+2RcpUkoBTbjIaImnQ+jX+/6p1vXcJ5geE=";
    };
    # Forrige driver = nixpkgs unstable sin latest (610.57.04).
    previous = base.latest;
  };
})
