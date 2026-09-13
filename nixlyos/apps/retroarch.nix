{ pkgs, lib, config, nixlyUser, ... }:

# HTPC mode ships its own RetroArch (htpc/media.nix) with a larger core set
# and a declarative config; two retroarch wrappers in systemPackages would
# collide, so this desktop variant is off there.
lib.mkIf (config.nixlyos.mode != "htpc") {
  # RetroArch with cores, XMB theme and udev joypad autoconfig; config is written
  # on each home-manager activation, so in-app tweaks last until the next rebuild.

  environment.systemPackages = with pkgs; [
    # availableOn: drop cores without an ARM build (parallel-n64) on SBCs
    # instead of failing the eval.
    (retroarch.withCores (cores: builtins.filter (lib.meta.availableOn stdenv.hostPlatform) [
      # N64
      cores.mupen64plus
      cores.parallel-n64

      # NES
      cores.nestopia
      cores.fceumm

      # SNES
      cores.snes9x
      cores.bsnes

      # Bonus retro coverage.
      cores.genesis-plus-gx       # Mega Drive / SMS / Game Gear
      cores.gambatte              # GB / GBC
      cores.mgba                  # GBA
      cores.beetle-psx-hw         # PlayStation 1 (Vulkan/HW)
    ]))

    retroarch-assets           # XMB icons, fonts, menu assets
    retroarch-joypad-autoconfig
  ];

  # udev rules and bluetooth come from gaming.nix, not duplicated here.

  home-manager.users.${nixlyUser} = { lib, ... }: {
    home.activation.retroarchConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      RA_CFG_DIR="$HOME/.config/retroarch"
      mkdir -p "$RA_CFG_DIR"
      mkdir -p "$RA_CFG_DIR/cores"
      mkdir -p "$RA_CFG_DIR/system"
      mkdir -p "$RA_CFG_DIR/saves"
      mkdir -p "$RA_CFG_DIR/states"
      mkdir -p "$RA_CFG_DIR/screenshots"
      mkdir -p "$RA_CFG_DIR/playlists"
      mkdir -p "$RA_CFG_DIR/thumbnails"

      cat > "$RA_CFG_DIR/retroarch.cfg" << 'RACFG'
      # Menu / theme
      menu_driver = "xmb"
      # Icon pack 0 is monochrome; switch under Appearance in-app.
      menu_xmb_theme = "0"
      menu_xmb_menu_color_theme = "1"
      menu_xmb_shadows_enable = "true"
      menu_xmb_ribbon_enable = "1"
      menu_horizontal_animation = "true"
      menu_show_load_core = "true"
      menu_show_load_content = "true"
      menu_show_online_updater = "true"
      menu_show_core_updater = "true"
      menu_enable_widgets = "true"
      menu_widget_scale_auto = "true"
      rgui_show_start_screen = "false"
      quick_menu_show_save_load_state = "true"
      quick_menu_show_take_screenshot = "true"

      # Per-system XMB wallpapers (NES/SNES/N64/etc backgrounds).
      menu_dynamic_wallpaper_enable = "true"
      dynamic_wallpapers_directory = "${pkgs.retroarch-assets}/share/retroarch/assets/wallpapers"

      # Thumbnail display in playlists/XMB (boxart on right, snap on left).
      menu_thumbnails = "3"
      menu_left_thumbnails = "2"
      menu_rgui_thumbnail_downscaler = "1"
      playlist_show_sublabels = "true"

      # XMB asset paths (provided by retroarch-assets)
      assets_directory = "${pkgs.retroarch-assets}/share/retroarch/assets"
      xmb_font = ""

      # Video
      video_driver = "vulkan"
      video_fullscreen = "true"
      # Real fullscreen covers the layer-shell top; windowed-fullscreen does not.
      video_windowed_fullscreen = "false"
      video_vsync = "true"
      video_threaded = "true"
      video_smooth = "true"
      video_scale_integer = "false"
      video_aspect_ratio_auto = "true"
      # Pure vsync: triple buffering plus auto frame delay, no VRR runloop.
      video_max_swapchain_images = "3"
      video_frame_delay = "0"
      video_frame_delay_auto = "true"
      video_hard_sync = "false"
      vrr_runloop_enable = "false"
      fastforward_ratio = "0.0"
      video_shader_enable = "true"
      video_shader_dir = "$HOME/.config/retroarch/shaders"

      # Audio
      audio_driver = "pipewire"
      audio_enable = "true"
      audio_sync = "true"
      audio_volume = "0.0"

      # Input / controllers
      input_driver = "udev"
      input_joypad_driver = "udev"
      input_autodetect_enable = "true"
      input_auto_remaps_enable = "true"
      input_max_users = "4"
      input_menu_toggle_gamepad_combo = "4"   # L3 + R3 → menu
      input_overlay_enable = "false"
      input_bluetooth_driver = "bluez"

      # Autoconfig profiles directory (xpad, dualshock, etc.)
      joypad_autoconfig_dir = "${pkgs.retroarch-joypad-autoconfig}/share/libretro/autoconfig"

      # Core / content paths
      libretro_directory = "$HOME/.config/retroarch/cores"
      libretro_info_path = "$HOME/.config/retroarch/cores"
      system_directory = "$HOME/.config/retroarch/system"
      savefile_directory = "$HOME/.config/retroarch/saves"
      savestate_directory = "$HOME/.config/retroarch/states"
      screenshot_directory = "$HOME/.config/retroarch/screenshots"
      playlist_directory = "$HOME/.config/retroarch/playlists"
      thumbnails_directory = "$HOME/.config/retroarch/thumbnails"

      # Online updater: lets the in-app updater fetch icon and thumbnail packs.
      network_on_demand_thumbnails = "true"
      core_updater_buildbot_url = "https://buildbot.libretro.com/nightly/linux/${pkgs.stdenv.hostPlatform.linuxArch}/latest/"
      core_updater_buildbot_assets_url = "https://buildbot.libretro.com/assets/"
      core_updater_auto_extract_archive = "true"
      core_updater_show_experimental_cores = "false"
      menu_show_core_updater = "true"
      automatically_add_content_to_playlist = "true"

      # Misc
      pause_nonactive = "false"
      check_firmware_before_loading = "false"
      auto_screenshot_filename = "true"
      savestate_auto_save = "true"
      savestate_auto_load = "true"
      config_save_on_exit = "true"
      RACFG

      # Per-core overrides to fill the 4K screen: 3D cores get the widescreen
      # hack below, 2D cores just stretch to 16:9.
      mkdir -p "$RA_CFG_DIR/config"

      for core in \
        "bsnes" "Snes9x" "FCEUmm" "Nestopia" \
        "Gambatte" "mGBA" "Genesis Plus GX" \
        "Mupen64Plus-Next" "ParaLLEl N64" "Beetle PSX HW"; do
        mkdir -p "$RA_CFG_DIR/config/$core"
        cat > "$RA_CFG_DIR/config/$core/$core.cfg" << 'CORECFG'
      aspect_ratio_index = "1"
      video_fullscreen = "true"
      video_windowed_fullscreen = "false"
      video_fullscreen_x = "0"
      video_fullscreen_y = "0"
      video_smooth = "true"
      video_force_aspect = "true"
      video_scale_integer = "false"
      CORECFG
      done

      # upsert_opt preserves the user's in-app tweaks to other keys.
      upsert_opt() {
        local file="$1" key="$2" value="$3"
        mkdir -p "$(dirname "$file")"
        touch "$file"
        if grep -q "^$key = " "$file" 2>/dev/null; then
          sed -i "s|^$key = .*|$key = \"$value\"|" "$file"
        else
          echo "$key = \"$value\"" >> "$file"
        fi
      }

      # Mupen64Plus-Next: true widescreen via projection-matrix hack
      M64="$RA_CFG_DIR/config/Mupen64Plus-Next/Mupen64Plus-Next.opt"
      upsert_opt "$M64" "mupen64plus-aspect" "16:9 adjusted"
      upsert_opt "$M64" "mupen64plus-169screensize" "1920x1080"
      upsert_opt "$M64" "mupen64plus-parallel-rdp-upscaling" "4x"
      upsert_opt "$M64" "mupen64plus-MultiSampling" "4"
      upsert_opt "$M64" "mupen64plus-Framerate" "Original"

      # ParaLLEl N64: widescreen hint + 4x RDP upscale
      PN64="$RA_CFG_DIR/config/ParaLLEl N64/ParaLLEl N64.opt"
      upsert_opt "$PN64" "parallel-n64-aspectratiohint" "widescreen"
      upsert_opt "$PN64" "parallel-n64-screensize" "1920x1080"
      upsert_opt "$PN64" "parallel-n64-parallel-rdp-upscaling" "4x"
      upsert_opt "$PN64" "parallel-n64-framerate" "original"

      # Beetle PSX HW: widescreen hack, 4x internal and PGXP, CPU freq left at 100 %.
      BPSX="$RA_CFG_DIR/config/Beetle PSX HW/Beetle PSX HW.opt"
      upsert_opt "$BPSX" "beetle_psx_hw_renderer" "hardware"
      upsert_opt "$BPSX" "beetle_psx_hw_renderer_software_fb" "enabled"
      upsert_opt "$BPSX" "beetle_psx_hw_internal_resolution" "4x"
      upsert_opt "$BPSX" "beetle_psx_hw_widescreen_hack" "enabled"
      upsert_opt "$BPSX" "beetle_psx_hw_widescreen_hack_aspect_ratio" "16:9"
      upsert_opt "$BPSX" "beetle_psx_hw_filter" "bilinear"
      upsert_opt "$BPSX" "beetle_psx_hw_dither_mode" "internal resolution"
      upsert_opt "$BPSX" "beetle_psx_hw_msaa" "4x"
      upsert_opt "$BPSX" "beetle_psx_hw_pgxp_mode" "memory only"
      upsert_opt "$BPSX" "beetle_psx_hw_pgxp_vertex" "enabled"
      upsert_opt "$BPSX" "beetle_psx_hw_pgxp_texture" "enabled"
      upsert_opt "$BPSX" "beetle_psx_hw_adaptive_smoothing" "enabled"
      upsert_opt "$BPSX" "beetle_psx_hw_cpu_freq_scale" "100%(native)"
      upsert_opt "$BPSX" "beetle_psx_hw_skip_bios" "enabled"
      upsert_opt "$BPSX" "beetle_psx_hw_frame_duping" "enabled"

      # bsnes HD Mode 7: only SNES core with internal upscaling
      BSNES="$RA_CFG_DIR/config/bsnes/bsnes.opt"
      upsert_opt "$BSNES" "bsnes_mode7_scale" "8x"
      upsert_opt "$BSNES" "bsnes_mode7_perspective" "ON"
      upsert_opt "$BSNES" "bsnes_mode7_supersample" "ON"
      upsert_opt "$BSNES" "bsnes_mode7_mosaic" "ON"
      upsert_opt "$BSNES" "bsnes_ips_headered" "ON"

      # xBR upscale for 2D cores; the path only resolves after Update Slang Shaders.
      SHADER="$HOME/.config/retroarch/shaders/shaders_slang/xbr/xbr-lv2-multipass.slangp"
      for core in \
        "bsnes" "Snes9x" "FCEUmm" "Nestopia" \
        "Gambatte" "mGBA" "Genesis Plus GX"; do
        CFG="$RA_CFG_DIR/config/$core/$core.cfg"
        upsert_opt "$CFG" "video_shader_enable" "true"
        upsert_opt "$CFG" "video_shader" "$SHADER"
      done
    '';
  };
}
