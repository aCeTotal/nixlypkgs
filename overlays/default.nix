inputs: final: prev:
let
  callPackage = final.callPackage;
in {
  speedtree = callPackage ../pkgs/speedtree { };
  nixlytile = callPackage ../pkgs/nixlytile { };
  nixlycc = callPackage ../pkgs/nixlycc { };
  nixly_launcher = callPackage ../pkgs/nixly_launcher {
    src = inputs.nixly_launcher_src;
  };
  nixly_lockscreen = callPackage ../pkgs/nixly_lockscreen { };
  claude = callPackage ../pkgs/claude { };
  nixlymediaserver = callPackage ../pkgs/nixlymediaserver { };
  nixlymedia = callPackage ../pkgs/nixlymedia { };
  citrix-workspace-nixly = callPackage ../pkgs/citrix-workspace-nixly { };
  geforce-now = callPackage ../pkgs/geforce-now { };
  libepoxy-nixly = callPackage ../pkgs/libepoxy { };
  Blender_bin_lts = callPackage ../pkgs/blender_bin_lts { };
  Unreal_editor = callPackage ../pkgs/unreal_editor { };
  gaea = callPackage ../pkgs/gaea { };
  kmymoney = callPackage ../pkgs/kmymoney { };
  low-latency-layer = callPackage ../pkgs/low-latency-layer { };
  proton-nixlyos = callPackage ../pkgs/proton-nixlyos { };
  proton-nixlyos-generic = callPackage ../pkgs/proton-nixlyos { variant = "generic"; };

  linux-nixlyos = (import ../pkgs/linux-nixlyos { kernelFlake = inputs.nixlyos-kernel; }).generic;
  linux-nixlyos-v3 = (import ../pkgs/linux-nixlyos { kernelFlake = inputs.nixlyos-kernel; }).v3;
  linuxPackages_nixlyos = import ./nvidia-latest.nix inputs final final.linux-nixlyos;
  linuxPackages_nixlyos_v3 = import ./nvidia-latest.nix inputs final final.linux-nixlyos-v3;

  # MIDLERTIDIG (crash-debug): siste CachyOS-kernel med matchende NVIDIA-driver,
  # begge ferdigbygd av chaotic-nyx. Settet maa komme fra chaotic sin egen
  # nixpkgs-pin med deres overlay: bare da blir store-pathene identiske med det
  # som ligger i nyx-cache.chaotic.cx, og verken kernel eller driver bygges
  # lokalt. allowUnfree (pkgs-config) maa settes her fordi kernel-settet arver
  # kernelens stdenv, og chaotic sin instans ellers nekter nvidia-x11.
  # Se base/boot.nix.
  linuxPackages_cachyos_nyx =
    (import inputs.chaotic.inputs.nixpkgs {
      inherit (final.stdenv.hostPlatform) system;
      config = import ../nixlyos/lib/pkgs-config.nix;
      overlays = [ inputs.chaotic.overlays.default ];
    }).linuxPackages_cachyos;

  flycast = prev.flycast.overrideAttrs (old: {
    postPatch = (old.postPatch or "") + ''
      sed -i '/#include "spvIR.h"/a #include <cstdint>' core/deps/glslang/SPIRV/SpvBuilder.h
    '';
  });
}
