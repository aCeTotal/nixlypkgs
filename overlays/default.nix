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
  libepoxy-nixly = callPackage ../pkgs/libepoxy { };
  Blender_bin_lts = callPackage ../pkgs/blender_bin_lts { };
  Unreal_editor = callPackage ../pkgs/unreal_editor { };
  gaea = callPackage ../pkgs/gaea { };
  kmymoney = callPackage ../pkgs/kmymoney { };
  low-latency-layer = callPackage ../pkgs/low-latency-layer { };
  nixly-mic = callPackage ../pkgs/nixly-mic { };
  nixly-gate = callPackage ../pkgs/nixly-gate { };
  # Streaming VAD needs whisper 1.9.
  nixly_voice = inputs.nixpkgs.legacyPackages.${final.stdenv.hostPlatform.system}.callPackage ../pkgs/nixly_voice {
    src = inputs.nixly_voice_src;
  };
  nixly_kalk = callPackage ../pkgs/nixly_kalk { };
  nixly_pdf = callPackage ../pkgs/nixly_pdf { };
  proton-nixlyos = callPackage ../pkgs/proton-nixlyos { };
  proton-nixlyos-generic = callPackage ../pkgs/proton-nixlyos { variant = "generic"; };

  linux-nixlyos = (import ../pkgs/linux-nixlyos { kernelFlake = inputs.nixlyos-kernel; }).generic;
  linux-nixlyos-v3 = (import ../pkgs/linux-nixlyos { kernelFlake = inputs.nixlyos-kernel; }).v3;
  linuxPackages_nixlyos = import ./nvidia-latest.nix inputs final final.linux-nixlyos;
  linuxPackages_nixlyos_v3 = import ./nvidia-latest.nix inputs final final.linux-nixlyos-v3;
  linux-nixlyserver = import ../pkgs/linux-nixlyserver { inherit (final) lib linux; };
  linuxPackages_nixlyserver = final.linuxPackagesFor final.linux-nixlyserver;

  # bluez 5.86 drops BLE HID setup on ATT 0x0E; patch retries the read.
  bluez-nixly = prev.bluez.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [ ../pkgs/bluez/hog-retry.patch ];
  });

  flycast = prev.flycast.overrideAttrs (old: {
    postPatch = (old.postPatch or "") + ''
      sed -i '/#include "spvIR.h"/a #include <cstdint>' core/deps/glslang/SPIRV/SpvBuilder.h
    '';
  });
}
