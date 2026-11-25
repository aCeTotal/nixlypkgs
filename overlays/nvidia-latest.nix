# NVIDIA fra unstable, bygget mot nixlyos-kernelen.
inputs: final: kernel:
let
  unstable = import inputs.nixpkgs {
    inherit (final.stdenv.hostPlatform) system;
    # Samme lisens-gating som maskinene.
    config = import ../nixlyos/lib/pkgs-config.nix;
  };
  base = (unstable.linuxPackagesFor kernel).nvidiaPackages;
  # Clang-moduler uten byggstier.
  portable = driver: driver.overrideAttrs (old: {
    postPatch = toString (old.postPatch or "") + ''
      substituteInPlace kernel/nvidia/nvidia.Kbuild \
        --replace-fail '$(CC) -v 2>&1 | tail -n 1' '$(CC) --version 2>&1 | head -n 1'
      echo 'ccflags-y += -fmacro-prefix-map=$(srctree)/=' >> kernel/Kbuild
    '';
  });
in
(final.linuxPackagesFor kernel).extend (_: _: {
  # previous er cachet reserve.
  nvidiaPackages = base // {
    latest = portable (base.mkDriver {
      version = "615.71.09";
      sha256_64bit = "sha256-zc7tIrvrYSSNGm3qvCWWZz46ZQFpjucayNL9wo87cP4=";
      sha256_aarch64 = "sha256-AARCH64";
      openSha256 = "sha256-3gByMYIwFzRaLdDG+roCEOuKRRJDrljG9AlLnRZTirM=";
      settingsSha256 = "sha256-LK1LU8mDkM/XVRKPBtuOZh9nIP/lGFLAJnmasEX8jhg=";
      persistencedSha256 = "sha256-qPRb+3d88+2RcpUkoBTbjIaImnQ+jX+/6p1vXcJ5geE=";
      # Fikser D3cold-krasj og 10 W-lås.
      patches = [ ./nvidia-nvpcf.patch ./nvidia-gps.patch ./nvidia-acpower.patch ];
    });
    previous = portable (base.mkDriver {
      version = "610.57.04";
      sha256_64bit = "sha256-suk1xmuDuwDAyFe8jg7g/VLekoa0DJzB7sKafOfrEW0=";
      sha256_aarch64 = "sha256-QCefrMBCmpOwuOyXv1k5Gj0iB2CYlPgnG3JToUw/j54=";
      openSha256 = "sha256-rQHOOOY4KL92Ww3KDwh+j4eGU7oNAH8LutZC5wmFnPo=";
      settingsSha256 = "sha256-ZEMo8I8Zc2Tq6RVDNYpAH+f094dUaZiBqO+5f6lIjRI=";
      persistencedSha256 = "sha256-aXmD2VY1RLlgAnlHhOUMWzvMyhI6JTClcFLm4imF/mA=";
    });
  };
})
