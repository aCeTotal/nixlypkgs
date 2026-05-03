inputs: final: prev:
let
  callPackage = final.callPackage;
in {
  speedtree = callPackage ../pkgs/speedtree { };
  nixlytile = callPackage ../pkgs/nixlytile { };
  nixly_launcher = callPackage ../pkgs/nixly_launcher {
    src = inputs.nixly_launcher_src;
  };
  claude = callPackage ../pkgs/claude { };
  nixlymediaserver = callPackage ../pkgs/nixlymediaserver { };
  citrix-workspace-nixly = callPackage ../pkgs/citrix-workspace-nixly { };
  nixly_steam = callPackage ../pkgs/nixly_steam { };
  libepoxy-nixly = callPackage ../pkgs/libepoxy { };
  blender_nixly = callPackage ../pkgs/blender_nixly { };
  kmymoney = callPackage ../pkgs/kmymoney { };

  # Fix flycast bundled glslang missing <cstdint> for GCC 15
  flycast = prev.flycast.overrideAttrs (old: {
    postPatch = (old.postPatch or "") + ''
      sed -i '/#include "spvIR.h"/a #include <cstdint>' core/deps/glslang/SPIRV/SpvBuilder.h
    '';
  });

  # Fix minizip pkg-config Cflags to include the minizip/ subdirectory
  minizip = prev.minizip.overrideAttrs (old: {
    postFixup = (old.postFixup or "") + ''
      sed -i 's|^Cflags:.*|Cflags: -I''${prefix}/include/minizip|' $out/lib/pkgconfig/minizip.pc
    '';
  });
}
