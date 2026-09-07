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

  linux-nixlyos = (import ../pkgs/linux-nixlyos { kernelFlake = inputs.nixlyos-kernel; }).generic;
  linux-nixlyos-v3 = (import ../pkgs/linux-nixlyos { kernelFlake = inputs.nixlyos-kernel; }).v3;
  linuxPackages_nixlyos = final.linuxPackagesFor final.linux-nixlyos;
  linuxPackages_nixlyos_v3 = final.linuxPackagesFor final.linux-nixlyos-v3;

  flycast = prev.flycast.overrideAttrs (old: {
    postPatch = (old.postPatch or "") + ''
      sed -i '/#include "spvIR.h"/a #include <cstdint>' core/deps/glslang/SPIRV/SpvBuilder.h
    '';
  });
}
