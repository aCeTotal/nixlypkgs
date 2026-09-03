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

  flycast = prev.flycast.overrideAttrs (old: {
    postPatch = (old.postPatch or "") + ''
      sed -i '/#include "spvIR.h"/a #include <cstdint>' core/deps/glslang/SPIRV/SpvBuilder.h
    '';
  });
}
