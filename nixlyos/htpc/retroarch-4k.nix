# RetroArch 4K TV picture quality. Two mechanisms:
#
# 2D systems (NES/SNES/GBA/GB): xBR-lv2 edge smoothing via automatic
# per-core shader presets — RetroArch loads config/<library name>/
# <library name>.slangp when that core starts (the video_shader key in
# retroarch.cfg has been ignored since 1.8). 3D cores get NO shader:
# they upscale internally instead, where it actually adds detail.
#
# 3D systems: internal render resolution near 4K through core options.
# Option keys and value strings are verified against the exact core
# binaries in the pinned nixpkgs — the value must match the core's
# definition character by character or it silently falls back to 1x.
# The file is a store symlink, so menu changes to core options do not
# survive a restart; per-game overrides (saved under config/) still do.
{ pkgs, lib, config, nixlyUser, ... }:

let
  xbr = "${pkgs.libretro-shaders-slang}/share/libretro/shaders/shaders_slang/edge-smoothing/xbr/xbr-lv2.slangp";
  preset2d = core: {
    "retroarch/config/${core}/${core}.slangp".text = ''
      #reference "${xbr}"
    '';
  };
in
lib.mkIf (config.nixlyos.mode == "htpc") {

  home-manager.users.${nixlyUser} = {
    xdg.configFile = lib.mkMerge [
      # Library names as reported by the cores themselves.
      (preset2d "Nestopia")
      (preset2d "Snes9x")
      (preset2d "mGBA")
      (preset2d "Gambatte")
      {
        "retroarch/retroarch-core-options.cfg".text = ''
          # N64: paraLLEl-RDP on Vulkan, 8x internal (~1920p, VI scales to 4K).
          mupen64plus-rdp-plugin = "parallel"
          mupen64plus-parallel-rdp-upscaling = "8x"

          # PS2: 6x internal resolution = ~2160p.
          pcsx2_upscale_multiplier = "6x Native (~2160p/4K)"

          # GC/Wii: 6x EFB scale = 3840x3168. Drop to "4x Native
          # (2560x2112) for 1440p" if a Wii title stutters.
          dolphin_efb_scale = "6x Native (3840x3168) for 4K"
        '';
      }
    ];
  };
}
