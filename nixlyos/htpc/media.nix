# HTPC A/V stack: RetroArch (full core set, 4K XMB), mpv for nixlymedia
# playback, and always-100%-unmuted sinks. apps/retroarch.nix (the smaller
# desktop RetroArch) is disabled in htpc mode so the two never collide.
{ pkgs, lib, config, nixlyUser, ... }:

let
  # The guide button belongs to nixlytile alone (htpc_guide.c app
  # menu): strip RetroArch's guide→menu bind from every controller
  # profile. The RetroArch menu is still reachable with L3+R3
  # (input_menu_toggle_gamepad_combo below).
  joypadAutoconfigNoGuide =
    pkgs.runCommand "retroarch-joypad-autoconfig-noguide" { } ''
      cp -r ${pkgs.retroarch-joypad-autoconfig} $out
      chmod -R u+w $out
      find $out -name '*.cfg' \
        -exec sed -i '/^input_menu_toggle_btn/d' {} +
    '';
in
lib.mkIf (config.nixlyos.mode == "htpc") {

  # RetroArch only; mpv comes from home-manager below.
  environment.systemPackages =
    (with pkgs; [
      nixlymedia
      (import ./retroarch-full.nix { inherit pkgs; })
      retroarch-assets
      retroarch-joypad-autoconfig
      libretro-shaders-slang
    ]);

  # The Intel Arc VAAPI/Vulkan stack lives in hardware/gpu/intel.nix.

  # Home-manager configs for the user
  home-manager.users.${nixlyUser} = { pkgs, ... }: {

    # RetroArch: XMB menu, 4K fullscreen Vulkan on Intel Arc, pipewire audio.
    xdg.configFile."retroarch/retroarch.cfg".text = ''
      # Video: Vulkan on Intel Arc, 4K fullscreen
      video_driver = "vulkan"
      video_fullscreen = "true"
      video_windowed_fullscreen = "false"
      video_fullscreen_x = "3840"
      video_fullscreen_y = "2160"
      video_vsync = "true"
      video_adaptive_vsync = "true"
      video_hard_sync = "false"
      video_max_swapchain_images = "3"
      video_threaded = "true"
      video_frame_delay = "0"
      video_frame_delay_auto = "true"
      video_gpu_screenshot = "true"
      video_shared_context = "true"

      # Scaling: fill 4K, preserve PAR, smooth pixels
      video_aspect_ratio_auto = "true"
      aspect_ratio_index = "22"
      video_scale_integer = "false"
      video_smooth = "true"
      video_ctx_scaling = "true"
      video_force_aspect = "true"

      # Shaders: per-core auto presets in retroarch-4k.nix (xBR on 2D
      # cores only — the global video_shader key is ignored since RA 1.8,
      # and 3D cores upscale internally instead).
      video_shader_enable = "true"
      video_shader_dir = "${pkgs.libretro-shaders-slang}/share/libretro/shaders/shaders_slang"

      # Audio
      # audio_volume in dB, 0.0 = unity = 100%
      audio_driver = "pipewire"
      audio_enable = "true"
      audio_sync = "true"
      audio_volume = "0.0"
      audio_mute_enable = "false"
      audio_latency = "32"

      # Menu: XMB (PS3-style) with neoactive icons, electric blue
      menu_driver = "xmb"
      xmb_theme = "4"
      xmb_menu_color_theme = "4"
      menu_show_load_content = "true"
      menu_show_quit_retroarch = "true"
      menu_show_restart_retroarch = "true"
      menu_show_online_updater = "true"
      menu_show_core_updater = "true"
      quit_press_twice = "false"
      menu_enable_widgets = "true"
      menu_widget_scale_auto = "true"

      # Input
      input_max_users = "4"
      input_autodetect_enable = "true"
      input_joypad_driver = "sdl2"
      input_menu_toggle_gamepad_combo = "2"

      # Savestates
      savestate_auto_save = "true"
      savestate_auto_load = "true"
      savestate_thumbnail_enable = "true"

      # Misc
      pause_nonactive = "false"
      fps_show = "false"

      # Asset / autoconfig paths
      assets_directory = "${pkgs.retroarch-assets}/share/retroarch/assets"
      joypad_autoconfig_dir = "${joypadAutoconfigNoGuide}/share/libretro/autoconfig"

      # Playlists: auto-generated from the NFS ROM share (playlists.nix),
      # one per system, every entry pinned to its core.
      playlist_directory = "~/.config/retroarch/playlists"
      content_show_playlists = "true"
    '';

    # mpv: 4K60 on Arc via gpu-next, Vulkan and VAAPI, with display-resample and
    # interpolation to kill 24/25/30p judder against the 60 Hz panel.
    programs.mpv = {
      enable = true;

      # mkForce: apps/mpv.nix (desktop defaults) also sets programs.mpv.config;
      # on the HTPC this TV-tuned config owns every key.
      config = lib.mkForce {
        # Operational
        idle = "no";
        terminal = "no";
        force-window = "immediate";
        osc = "yes";
        pause = "no";
        hr-seek = "yes";
        save-position-on-quit = "no";
        msg-level = "all=v";
        log-file = "/tmp/mpv.log";
        ao = "pipewire";

        # Output: Vulkan + gpu-next on Arc A770
        vo = "gpu-next";
        gpu-api = "vulkan";
        gpu-context = "auto";
        # vaapi-copy avoids the pool contention that stuttered motion scenes on the A770.
        hwdec = "vaapi-copy";
        vd-lavc-dr = "no";
        hwdec-codecs = "all";
        vulkan-swap-mode = "fifo";
        swapchain-depth = 3;
        gpu-shader-cache-dir = "~/.cache/mpv/shaders";

        # Display: fullscreen 4K@60 on TV
        fullscreen = "yes";
        keep-open = "yes";
        cursor-autohide = 500;

        # Frame timing: display-resample retimes audio, oversample phase-blends 24 to 60.
        video-sync = "display-resample";
        interpolation = "yes";
        tscale = "oversample";
        framedrop = "no";
        video-latency-hacks = "no";
        hr-seek-framedrop = "no";

        # Scaling: high-quality upscale to 4K on Arc
        scale = "ewa_lanczossharp";
        cscale = "ewa_lanczossoft";
        dscale = "mitchell";
        correct-downscaling = "yes";
        linear-downscaling = "yes";
        sigmoid-upscaling = "yes";
        dither-depth = "auto";
        deband = "yes";
        deband-iterations = 1;
        deband-threshold = 35;
        deband-range = 16;
        deband-grain = 4;

        # HDR passthrough (no-op on SDR TV)
        target-colorspace-hint = "yes";
        target-peak = "auto";
        hdr-compute-peak = "no";
        tone-mapping = "bt.2446a";
        gamut-mapping-mode = "perceptual";

        # Audio
        # Always decode to PCM, and never take the sink exclusively, so WirePlumber
        # route changes cannot silence mpv.
        audio-channels = "auto";
        audio-exclusive = "no";
        volume = "100";
        volume-max = "100";

        # Cache: HTTP stream from nixlymediaserver
        # A 64 MiB receive buffer absorbs network jitter that starves 4K bitrates.
        cache = "yes";
        cache-secs = 180;
        cache-pause = "yes";
        cache-pause-wait = 1;
        cache-pause-initial = "no";
        cache-on-disk = "no";
        demuxer-max-bytes = "1GiB";
        demuxer-max-back-bytes = "128MiB";
        demuxer-readahead-secs = 60;
        demuxer-seekable-cache = "yes";
        demuxer-hysteresis-secs = 10;
        stream-buffer-size = "64MiB";
        network-timeout = 60;
        prefetch-playlist = "yes";

        # Subs / audio language priority
        sub-auto = "fuzzy";
        slang = "no,nob,en,eng";
        alang = "no,nob,en,eng";

        # Subtitle styling (smaller text)
        sub-font-size = 30;
        sub-border-size = 2;
        sub-shadow-offset = 0;

        # Screenshots
        screenshot-format = "png";
        screenshot-directory = "~/Pictures/mpv";
      };
    };

    # Force every sink to 80 % unmuted once WirePlumber is live.
    systemd.user.services.htpc-audio-unmute =
      let
        setAllSinks = pkgs.writeShellScript "htpc-audio-set-all-sinks-80" ''
          set -u
          WPCTL=${pkgs.wireplumber}/bin/wpctl
          "$WPCTL" status | ${pkgs.gawk}/bin/awk '
            /Sinks:/ {insinks=1; next}
            /Sources:/ {insinks=0}
            insinks && match($0, /[0-9]+\./) {
              id=substr($0, RSTART, RLENGTH-1); print id
            }
          ' | while read -r id; do
            "$WPCTL" set-mute   "$id" 0   || true
            "$WPCTL" set-volume "$id" 0.8 || true
          done
        '';
      in {
        Unit = {
          Description = "HTPC: unmute all sinks and set volume to 80%";
          After = [ "graphical-session.target" "wireplumber.service" ];
          PartOf = [ "graphical-session.target" ];
        };
        Install.WantedBy = [ "graphical-session.target" ];
        Service = {
          Type = "oneshot";
          ExecStart = pkgs.writeShellScript "htpc-audio-unmute" ''
            set -u
            WPCTL=${pkgs.wireplumber}/bin/wpctl
            for _ in 1 2 3 4 5; do
              "$WPCTL" get-volume @DEFAULT_AUDIO_SINK@ >/dev/null 2>&1 && break
              sleep 1
            done
            ${setAllSinks}
          '';
        };
      };

    # New sinks are forced to 80 % unmuted; existing ones are left alone.
    systemd.user.services.htpc-audio-watch = {
      Unit = {
        Description = "HTPC: force new audio sinks to 80% unmuted";
        After = [ "htpc-audio-unmute.service" "pipewire.service" ];
        PartOf = [ "graphical-session.target" ];
      };
      Install.WantedBy = [ "graphical-session.target" ];
      Service = {
        Type = "simple";
        Restart = "on-failure";
        RestartSec = 2;
        ExecStart = pkgs.writeShellScript "htpc-audio-watch" ''
          set -u
          WPCTL=${pkgs.wireplumber}/bin/wpctl
          ${pkgs.pulseaudio}/bin/pactl subscribe 2>/dev/null | while IFS= read -r line; do
            case "$line" in
              "Event 'new' on sink "*)
                sleep 0.3
                "$WPCTL" status | ${pkgs.gawk}/bin/awk '
                  /Sinks:/ {insinks=1; next}
                  /Sources:/ {insinks=0}
                  insinks && match($0, /[0-9]+\./) {
                    id=substr($0, RSTART, RLENGTH-1); print id
                  }
                ' | while read -r id; do
                  "$WPCTL" set-mute   "$id" 0   || true
                  "$WPCTL" set-volume "$id" 0.8 || true
                done
                ;;
            esac
          done
        '';
      };
    };
  };
}
