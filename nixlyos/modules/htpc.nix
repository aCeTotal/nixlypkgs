{ config, lib, pkgs, nixlyUser, ... }:

let
  # Intel iGPU PCI slot.
  igpuSlot = "0000:00:02.0";

  # Installed by media, kept warm.
  retroarchFull = pkgs.retroarch.withCores (cores: with cores; [
    nestopia
    snes9x
    bsnes
    genesis-plus-gx
    mupen64plus
    beetle-psx-hw
    pcsx-rearmed
    mgba
    gambatte
    beetle-saturn
    flycast
    melonds
    mame
    stella
    ppsspp
    fbneo
    # ROM share has these folders.
    pcsx2
    dolphin
  ]);

  # No greeter, ever.
  login = {
    services.displayManager.autoLogin = {
      enable = true;
      user = nixlyUser;
    };
    services.displayManager.sddm.autoLogin.relogin = true;
  };

  # One app at a time.
  session =
    let
      # Widest connected output becomes primary.
      setRandrPrimary = pkgs.writeShellScript "nixly-xrandr-primary" ''
        for _ in $(seq 10); do
          out=$(${pkgs.xrandr}/bin/xrandr 2>/dev/null \
            | sed -n 's/^\([^ ]*\) connected.* \([0-9]\+\)x[0-9]\++.*/\2 \1/p' \
            | sort -rn | head -1 | cut -d' ' -f2)
          if [ -n "$out" ] && ${pkgs.xrandr}/bin/xrandr --output "$out" --primary 2>/dev/null; then
            exit 0
          fi
          sleep 1
        done
      '';

      # Supervisor: restarts the app on exit.
      htpcLoop = pkgs.writeShellScript "htpc-loop" ''
        app="$1"
        while :; do
          case "$app" in
            steam)
              ${setRandrPrimary} &
              steam -tenfoot
              ;;
            geforcenow) nixly-gfn ;;
            nixlymedia) nixlymedia ;;
            *)          retroarch ;;
          esac
          # A boot-looping app must not spin.
          sleep 0.3
        done
      '';

      htpcSwitch = pkgs.writeShellScriptBin "htpc-switch" ''
        app="$1"
        uid=$(${pkgs.coreutils}/bin/id -u)
        cg=/sys/fs/cgroup/user.slice/user-$uid.slice/user@$uid.service

        for kill in "$cg"/app.slice/htpc-app-*.scope/cgroup.kill \
                    "$cg"/app.slice/app-flatpak-com.nvidia.geforcenow-*.scope/cgroup.kill; do
          [ -e "$kill" ] && echo 1 > "$kill"
        done

        # GFN runs outside our scope.
        if grep -q '^populated 1' "$cg/gfn.slice/cgroup.events" 2>/dev/null; then
          echo 1 > "$cg/gfn.slice/cgroup.kill"
          ${pkgs.systemd}/bin/systemctl stop --no-block gfn-focus.service 2>/dev/null || true
        fi

        # RP1 for media, full for games.
        htpc-gpu-clock "$app" 2>/dev/null || true

        exec ${pkgs.systemd}/bin/systemd-run --user --scope --quiet --collect \
          --slice=app.slice --unit="htpc-app-$app-$$" -- ${htpcLoop} "$app"
      '';
    in
    {
      environment.systemPackages = [ htpcSwitch ];
    }
  ;

  # RetroArch, mpv, unmuted sinks.
  media =
    let
      # Guide button belongs to nixlytile.
      joypadAutoconfigNoGuide =
        pkgs.runCommand "retroarch-joypad-autoconfig-noguide" { } ''
          cp -r ${pkgs.retroarch-joypad-autoconfig} $out
          chmod -R u+w $out
          find $out -name '*.cfg' \
            -exec sed -i '/^input_menu_toggle_btn/d' {} +
        '';
    in
    {

      environment.systemPackages =
        (with pkgs; [
          nixlymedia
          retroarchFull
          retroarch-assets
          retroarch-joypad-autoconfig
          libretro-shaders-slang
        ]);

      home-manager.users.${nixlyUser} = { pkgs, ... }:
        let
          # wpctl's MUTED tag is unlocalized.
          unmuteMuted = pkgs.writeShellScript "htpc-audio-unmute-muted" ''
            set -u
            WPCTL=${pkgs.wireplumber}/bin/wpctl
            "$WPCTL" status | ${pkgs.gawk}/bin/awk '
              /Sinks:/   {on=1} /Sources:/ {on=1} /Streams:/ {on=1}
              /Filters:/ {on=0} /Video/    {on=0} /Settings/ {on=0}
              on && match($0, /[0-9]+\./) { print substr($0, RSTART, RLENGTH-1) }
            ' | sort -u | while read -r id; do
              "$WPCTL" get-volume "$id" 2>/dev/null \
                | ${pkgs.gnugrep}/bin/grep -q MUTED && "$WPCTL" set-mute "$id" 0 || true
            done
          '';

          # Every sink unmuted at 80 %.
          setAllSinks = pkgs.writeShellScript "htpc-audio-set-all-sinks-80" ''
            set -u
            WPCTL=${pkgs.wireplumber}/bin/wpctl
            "$WPCTL" status | ${pkgs.gawk}/bin/awk '
              /Sinks:/ {insinks=1; next}
              /Sources:/ {insinks=0}
              insinks && match($0, /[0-9]+\./) { print substr($0, RSTART, RLENGTH-1) }
            ' | while read -r id; do
              "$WPCTL" set-mute "$id" 0 || true
              "$WPCTL" set-volume "$id" 0.8 || true
            done
          '';
        in
        {

          # 4K Vulkan on Arc.
          xdg.configFile."retroarch/retroarch.cfg".text = ''
            video_driver = "vulkan"
            video_fullscreen = "true"
            video_windowed_fullscreen = "false"
            video_fullscreen_x = "3840"
            video_fullscreen_y = "2160"
            video_vsync = "true"
            video_adaptive_vsync = "true"
            video_hard_sync = "false"
            # Three images pinned 10 fps.
            video_max_swapchain_images = "4"
            # Adds a frame on Vulkan.
            video_threaded = "false"
            video_frame_delay = "0"
            video_frame_delay_auto = "true"
            video_gpu_screenshot = "true"
            video_shared_context = "true"

            video_aspect_ratio_auto = "true"
            aspect_ratio_index = "22"
            video_scale_integer = "false"
            video_smooth = "true"
            video_ctx_scaling = "true"
            video_force_aspect = "true"

            # Per-core presets set shaders.
            video_shader_enable = "true"
            video_shader_dir = "${pkgs.libretro-shaders-slang}/share/libretro/shaders/shaders_slang"

            # Volume in dB, 0 = unity.
            audio_driver = "pipewire"
            audio_enable = "true"
            audio_sync = "true"
            audio_volume = "0.0"
            audio_mute_enable = "false"
            audio_latency = "32"

            # XMB, neoactive, electric blue.
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

            input_max_users = "4"
            input_autodetect_enable = "true"
            input_joypad_driver = "sdl2"
            input_menu_toggle_gamepad_combo = "2"

            savestate_auto_save = "true"
            savestate_auto_load = "true"
            savestate_thumbnail_enable = "true"
            # Switching kills without flushing.
            autosave_interval = "10"

            pause_nonactive = "false"
            fps_show = "false"

            assets_directory = "${pkgs.retroarch-assets}/share/retroarch/assets"
            joypad_autoconfig_dir = "${joypadAutoconfigNoGuide}/share/libretro/autoconfig"

            # Written by apps/rom-playlists.
            playlist_directory = "~/.config/retroarch/playlists"
            content_show_playlists = "true"
          '';

          # No judder on the 60 Hz panel.
          programs.mpv = {
            enable = true;

            # Overrides the desktop mpv config.
            config = lib.mkForce {
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

              vo = "gpu-next";
              gpu-api = "vulkan";
              gpu-context = "auto";
              # Pool contention stuttered motion.
              hwdec = "vaapi-copy";
              vd-lavc-dr = "no";
              hwdec-codecs = "all";
              vulkan-swap-mode = "fifo";
              swapchain-depth = 3;
              gpu-shader-cache-dir = "~/.cache/mpv/shaders";

              fullscreen = "yes";
              keep-open = "yes";
              cursor-autohide = 500;

              # Blends 24p into 60 Hz.
              video-sync = "display-resample";
              interpolation = "yes";
              tscale = "oversample";
              framedrop = "no";
              video-latency-hacks = "no";
              hr-seek-framedrop = "no";

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

              target-colorspace-hint = "yes";
              target-peak = "auto";
              hdr-compute-peak = "no";
              tone-mapping = "bt.2446a";
              gamut-mapping-mode = "perceptual";

              # PCM, never an exclusive sink.
              audio-channels = "auto";
              audio-exclusive = "no";
              volume = "100";
              volume-max = "100";

              # Absorbs jitter at 4K bitrates.
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

              sub-auto = "fuzzy";
              slang = "no,nob,en,eng";
              alang = "no,nob,en,eng";

              sub-font-size = 30;
              sub-border-size = 2;
              sub-shadow-offset = 0;

              screenshot-format = "png";
              screenshot-directory = "~/Pictures/mpv";
            };
          };

          # Every sink at 80 %.
          systemd.user.services.htpc-audio-unmute = {
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
                ${unmuteMuted}
              '';
            };
          };

          # nixlymedia mutes its own stream.
          systemd.user.services.htpc-audio-watch = {
            Unit = {
              Description = "HTPC: keep sinks/sources/streams unmuted";
              After = [ "htpc-audio-unmute.service" "pipewire.service" ];
              PartOf = [ "graphical-session.target" ];
            };
            Install.WantedBy = [ "graphical-session.target" ];
            Service = {
              Type = "simple";
              # Exits cleanly when pulse restarts.
              Restart = "always";
              RestartSec = 2;
              ExecStart = pkgs.writeShellScript "htpc-audio-watch" ''
                set -u
                ${pkgs.pulseaudio}/bin/pactl subscribe 2>/dev/null | while IFS= read -r line; do
                  case "$line" in
                    "Event 'new' on sink "*)
                      sleep 0.3
                      ${setAllSinks}
                      ;;
                    "Event 'new' on sink-input "*|"Event 'change' on sink-input "*|"Event 'new' on source "*)
                      sleep 0.2
                      ${unmuteMuted}
                      ;;
                  esac
                done
              '';
            };
          };
        };
    }
  ;

  # Stereo to the TV.
  audio =
    {

      services.pipewire.wireplumber.extraConfig."55-htpc-hdmi-priority" = {
        "device.profile.priority.rules" = [
          {
            matches = [
              { "device.name" = "~alsa_card.*"; }
            ];
            actions = {
              update-props = {
                priorities = [ "output:hdmi-stereo" ];
              };
            };
          }
        ];
        "monitor.alsa.rules" = [
          {
            matches = [
              { "device.name" = "~alsa_card.*"; }
            ];
            actions = {
              update-props = {
                "api.acp.auto-port" = true;
              };
            };
          }
          {
            matches = [
              { "node.name" = "~alsa_output.*hdmi.*"; }
            ];
            actions = {
              update-props = {
                "priority.session" = 3000;
                "priority.driver" = 3000;
              };
            };
          }
        ];
      };

      # Saved surround state beats priorities.
      systemd.user.services.htpc-wp-state-reset = {
        description = "Remove saved surround profiles from WirePlumber state";
        before = [ "wireplumber.service" ];
        partOf = [ "wireplumber.service" ];
        wantedBy = [ "wireplumber.service" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = pkgs.writeShellScript "htpc-wp-state-reset" ''
            set -u
            D="''${XDG_STATE_HOME:-$HOME/.local/state}/wireplumber"
            [ -d "$D" ] || exit 0
            ${pkgs.gnused}/bin/sed -i '/hdmi-surround/d' \
              "$D/default-profile" "$D/default-routes" 2>/dev/null || true
          '';
        };
      };
    };

  # Modeset enables the codec.
  hdmiAudio =
    {
      # Idle mute.
      boot.extraModprobeConfig = ''
        options snd_hda_codec_intelhdmi enable_silent_stream=N
      '';

      systemd.services.htpc-hdmi-audio = {
        description = "Force a modeset so i915 enables the HDMI/DP audio codec";
        wantedBy = [ "multi-user.target" ];
        before = [ "display-manager.service" ];
        after = [ "sound.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = pkgs.writeShellScript "htpc-hdmi-audio" ''
            set -u
            GREP=${pkgs.gnugrep}/bin/grep

            eld_ok() {
              $GREP -lE 'eld_valid[[:space:]]+1' /proc/asound/card*/eld* 2>/dev/null \
                | $GREP -q .
            }

            connected() {
              for s in /sys/class/drm/card*-*/status; do
                [ "$(cat "$s" 2>/dev/null)" = connected ] || continue
                dirname "$s"
                return 0
              done
              return 1
            }

            # Connector and ELD files first.
            have_eld_files() {
              for f in /proc/asound/card*/eld*; do
                [ -e "$f" ] && return 0
              done
              return 1
            }

            for _ in $(seq 30); do
              connected >/dev/null && have_eld_files && break
              sleep 1
            done

            conn=$(connected) || exit 0

            for _ in $(seq 3); do
              eld_ok && exit 0
              echo off    > "$conn/status"
              sleep 2
              echo detect > "$conn/status"
              sleep 3
            done

            eld_ok || echo "htpc-hdmi-audio: ELD still invalid on $conn, TV has no audio" >&2
            exit 0
          '';
        };
      };
    };

  # Shared BIOS dumps from NFS.
  biosSync =
    {

      home-manager.users.${nixlyUser} = {
        systemd.user.services.htpc-bios-sync = {
          Unit.Description = "HTPC: sync BIOS files from NFS to RetroArch";
          Service = {
            Type = "oneshot";
            ExecStart = pkgs.writeShellScript "htpc-bios-sync" ''
              set -u
              src=/mnt/nfs/Bigdisk1/Emulator/BIOS
              dst="$HOME/.config/retroarch/system"
              # Keep earlier syncs when down.
              [ -d "$src" ] || exit 0
              mkdir -p "$dst"
              # Skip the original bundles.
              ${pkgs.rsync}/bin/rsync -rt --exclude 'README*' --exclude '_*' \
                "$src/" "$dst/"
            '';
          };
        };

        systemd.user.timers.htpc-bios-sync = {
          Unit.Description = "HTPC: periodic BIOS re-sync";
          Install.WantedBy = [ "timers.target" ];
          Timer = {
            OnStartupSec = "30s";
            OnUnitActiveSec = "30min";
          };
        };
      };
    };

  # 4K picture per core.
  retroarch4k =
    let
      xbr = "${pkgs.libretro-shaders-slang}/share/libretro/shaders/shaders_slang/edge-smoothing/xbr/xbr-lv2.slangp";
      preset2d = core: {
        "retroarch/config/${core}/${core}.slangp".text = ''
          #reference "${xbr}"
        '';
      };
    in
    {

      home-manager.users.${nixlyUser} = {
        xdg.configFile = lib.mkMerge [
          # Library names the cores report.
          (preset2d "Nestopia")
          (preset2d "Snes9x")
          (preset2d "mGBA")
          (preset2d "Gambatte")
          {
            # PS2 stretches to the panel.
            "retroarch/config/LRPS2/LRPS2.cfg".text = ''
              aspect_ratio_index = "24"
            '';
          }
          {
            "retroarch/retroarch-core-options.cfg".text = ''
              # N64 at 8x internal.
              mupen64plus-rdp-plugin = "parallel"
              mupen64plus-parallel-rdp-upscaling = "8x"

              # PS2 native, upscaling stalls readback.
              pcsx2_upscale_multiplier = "1x Native (PS2)"
              pcsx2_widescreen_hint = "enabled"

              # GC/Wii at 6x EFB.
              dolphin_efb_scale = "6x Native (3840x3168) for 4K"
            '';
          }
        ];
      };
    }
  ;

  # Arc pinned at RP1.
  gpuClocks =
    let
    in
    {
      systemd.services.htpc-gpu-clocks = {
        description = "Pin Intel Arc GPU clocks at RP1 (VRM noise on TV/eARC above)";
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = pkgs.writeShellScript "htpc-gpu-clocks" ''
            set -u
            # Waits for i915's knobs.
            pinned=0
            for _ in $(seq 60); do
              for card in /sys/class/drm/card*; do
                [ -e "$card/gt_RP0_freq_mhz" ] || continue
                rp1=$(cat "$card/gt_RP1_freq_mhz")
                cap=$rp1
                # iGPU has no card VRM.
                [ "$(basename "$(readlink -f "$card/device")")" = ${igpuSlot} ] \
                  && cap=$(cat "$card/gt_RP0_freq_mhz")
                # Max never drops below min.
                echo "$rp1" > "$card/gt_min_freq_mhz"   || true
                echo "$cap" > "$card/gt_max_freq_mhz"   || true
                echo "$cap" > "$card/gt_boost_freq_mhz" || true
                pinned=1
              done
              [ "$pinned" = 1 ] && break
              sleep 1
            done
            # Display devices stay awake.
            for dev in /sys/bus/pci/devices/*; do
              case "$(cat "$dev/class")" in
                0x03*) echo on > "$dev/power/control" || true ;;
              esac
            done
          '';
        };
      };
    }
  ;

  # Full range for games.
  gpuClock =
    let

      gpuClock = pkgs.writeShellScriptBin "htpc-gpu-clock" ''
        set -u
        case "''${1:-}" in
          steam|retroarch) mode=high ;;
          *)               mode=low  ;;
        esac

        for card in /sys/class/drm/card*; do
          [ -e "$card/gt_max_freq_mhz" ] || continue
          rp0=$(cat "$card/gt_RP0_freq_mhz" 2>/dev/null) || continue
          rp1=$(cat "$card/gt_RP1_freq_mhz" 2>/dev/null) || continue

          cap=$rp1
          [ "$mode" = high ] && cap=$rp0
          # iGPU has no card VRM.
          [ "$(basename "$(readlink -f "$card/device")")" = ${igpuSlot} ] && cap=$rp0

          # Max never drops below min.
          echo "$rp1" > "$card/gt_min_freq_mhz" 2>/dev/null || true
          echo "$cap" > "$card/gt_max_freq_mhz" 2>/dev/null || true
          echo "$cap" > "$card/gt_boost_freq_mhz" 2>/dev/null || true
        done
      '';

      perms = pkgs.writeShellScript "htpc-gpu-clock-perms" ''
        for f in /sys/class/drm/card*/gt_min_freq_mhz \
                 /sys/class/drm/card*/gt_max_freq_mhz \
                 /sys/class/drm/card*/gt_boost_freq_mhz; do
          [ -e "$f" ] || continue
          ${pkgs.coreutils}/bin/chgrp users "$f" 2>/dev/null || true
          ${pkgs.coreutils}/bin/chmod 0664 "$f" 2>/dev/null || true
        done
      '';
    in
    {
      environment.systemPackages = [ gpuClock ];

      systemd.services.htpc-gpu-clock-perms = {
        description = "Make GPU clock knobs writable for the users group";
        wantedBy = [ "multi-user.target" ];
        after = [ "htpc-gpu-clocks.service" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${perms}";
        };
      };

      # Late cards get the perms.
      services.udev.extraRules = ''
        ACTION=="add|change", SUBSYSTEM=="drm", KERNEL=="card[0-9]*", RUN+="${pkgs.systemd}/bin/systemctl --no-block restart htpc-gpu-clock-perms.service"
      '';
    }
  ;

  # Nightly update and reboot.
  autoUpdate =
    {

      systemd.services.nixlyos-autoupdate = {
        description = "NixlyOS nightly update + reboot (HTPC)";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        path = with pkgs; [ coreutils util-linux nix systemd nixlyos-panel ];
        serviceConfig.Type = "oneshot";
        script = ''
          set -u
          home=/home/${nixlyUser}
          stage="$home/.local/state/nixlyos/stage"
          flake="$home/.local/nixlyos"

          # Failures keep the earlier stage.
          runuser -u ${nixlyUser} -- /run/current-system/sw/bin/nixlyos-stage || true

          sys=$(readlink -f "$stage/result" 2>/dev/null || true)
          [ -n "$sys" ] && [ -e "$sys/bin/switch-to-configuration" ] || exit 0

          cur=$(readlink -f /run/current-system)
          booted=$(readlink -f /run/booted-system)
          [ "$sys" = "$cur" ] && [ "$sys" = "$booted" ] && exit 0

          if [ "$sys" != "$cur" ]; then
            # Keeps nixlyos-update's stamp valid.
            if [ -f "$stage/flake/flake.lock" ]; then
              if [ -f "$flake/profile" ]; then runuser -u ${nixlyUser} -- nixlyos-panel pin || true; fi
              runuser -u ${nixlyUser} -- cp "$stage/flake/flake.lock" "$flake/flake.lock" || true
              rm -f "$flake/pins.nix"
            fi
            nix-env -p /nix/var/nix/profiles/system --set "$sys"
            "$sys/bin/switch-to-configuration" boot
          fi

          # Kernel and session switch together.
          systemctl reboot
        '';
      };

      systemd.timers.nixlyos-autoupdate = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "*-*-* 06:00:00";
          # Never reboot under a viewer.
          Persistent = false;
          AccuracySec = "1min";
        };
      };
    };

  # Couch apps stay in RAM.
  prewarm =
    let
      raFull = retroarchFull;

      # Full runtime closures.
      closure = pkgs.writeClosure [
        raFull
        pkgs.nixlymedia
        pkgs.retroarch-assets
        pkgs.libretro-shaders-slang
      ];

      warmScript = pkgs.writeShellScript "htpc-prewarm" ''
        set -u
        VMTOUCH=${pkgs.vmtouch}/bin/vmtouch

        # Games own RAM and IO.
        ${pkgs.systemd}/bin/systemctl is-active -q nixly-gametune.service && exit 0
        ${pkgs.procps}/bin/pgrep -x wineserver >/dev/null 2>&1 && exit 0
        ${pkgs.procps}/bin/pgrep -x gamescope  >/dev/null 2>&1 && exit 0

        warm() {
          [ -e "$1" ] && "$VMTOUCH" -t -q -m 512M "$1" 2>/dev/null || true
        }

        while IFS= read -r p; do
          warm "$p"
        done < ${closure}

        # Flatpak app and runtime.
        warm /var/lib/flatpak/app/com.nvidia.geforcenow
        rt=$(${pkgs.flatpak}/bin/flatpak info --show-runtime com.nvidia.geforcenow 2>/dev/null || true)
        rt=''${rt#runtime/}
        [ -n "$rt" ] && warm "/var/lib/flatpak/runtime/$rt"
        exit 0
      '';
      # Off the boot path.
      firstWarmScript = pkgs.writeShellScript "htpc-prewarm-first" ''
        set -u
        VMTOUCH=${pkgs.vmtouch}/bin/vmtouch
        while IFS= read -r p; do
          [ -e "$p" ] && "$VMTOUCH" -t -q -m 512M "$p" 2>/dev/null || true
        done < ${closure}
        exit 0
      '';
    in
    {

      systemd.timers.htpc-prewarm-first = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          # Boot app owns the disk.
          OnBootSec = "20s";
          Persistent = false;
        };
      };

      systemd.services.htpc-prewarm-first = {
        description = "Warm the boot HTPC app (RetroArch/nixlymedia) at startup";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${firstWarmScript}";
          Slice = "background.slice";
          Nice = 19;
          CPUSchedulingPolicy = "idle";
          IOSchedulingClass = "idle";
          MemoryHigh = "25%";
        };
      };

      systemd.services.htpc-prewarm = {
        description = "Keep HTPC apps (RetroArch/nixlymedia/GeForce NOW) in RAM";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${warmScript}";
          Slice = "background.slice";
          Nice = 19;
          CPUSchedulingPolicy = "idle";
          IOSchedulingClass = "idle";
          # Reclaims its own pages first.
          MemoryHigh = "25%";
        };
      };

      systemd.timers.htpc-prewarm = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          # After Steam's cold start.
          OnBootSec = "3min";
          OnUnitActiveSec = "10min";
          Persistent = false;
        };
      };
    }
  ;

  # Open ROM pulled into RAM.
  romCache =
    {
      systemd.services.htpc-rom-cache = {
        description = "Pull the ROM the emulator has open into RAM";
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "simple";
          Restart = "always";
          RestartSec = 5;
          # Normal IO, or too late.
          Nice = 5;
          ExecStart = pkgs.writeShellScript "htpc-rom-cache" ''
            set -u
            warmed=""

            while :; do
              for pid in $(${pkgs.procps}/bin/pgrep -f retroarch); do
                for fd in /proc/$pid/fd/*; do
                  rom=$(readlink "$fd" 2>/dev/null) || continue
                  case "$rom" in
                    /mnt/nfs/*) ;;
                    *) continue ;;
                  esac
                  case " $warmed " in
                    *" $rom "*) continue ;;
                  esac
                  warmed="$warmed $rom"
                  # Largest ISO on the share.
                  ${pkgs.vmtouch}/bin/vmtouch -t -q -m 8G "$rom" 2>/dev/null &
                done
              done
              sleep 3
            done
          '';
        };
      };
    };

  # Pads pair themselves.
  controllers =
    let
      btAutopair = pkgs.writeShellScript "htpc-bt-autopair" ''
        set -u
        BT=${pkgs.bluez}/bin/bluetoothctl

        until "$BT" show | ${pkgs.gnugrep}/bin/grep -q "Powered: yes"; do
          sleep 2
        done
        "$BT" pairable on >/dev/null 2>&1 || true

        is_pad() { # $1 mac, $2 name — gamepad by bluez icon/appearance or name
          info=$("$BT" info "$1" 2>/dev/null) || return 1
          printf '%s' "$info" | ${pkgs.gnugrep}/bin/grep -qE \
            "Icon: input-gaming|Appearance: 0x03c" && return 0
          printf '%s' "$2" | ${pkgs.gnugrep}/bin/grep -qiE \
            "controller|gamepad|dualsense|dualshock|wireless gamepad|joy-con|8bitdo|xbox" \
            && return 0
          return 1
        }

        while :; do
          # Bursts keep scanning continuous.
          "$BT" --timeout 12 scan on >/dev/null 2>&1 || true

          paired=$("$BT" devices Paired 2>/dev/null | ${pkgs.gawk}/bin/awk '{print $2}')
          "$BT" devices 2>/dev/null | while read -r _ mac name; do
            [ -n "$mac" ] || continue
            printf '%s\n' "$paired" | ${pkgs.gnugrep}/bin/grep -qiF "$mac" && continue
            is_pad "$mac" "$name" || continue
            echo "pairing new controller: $name ($mac)"
            "$BT" pair "$mac" >/dev/null 2>&1 || continue
            "$BT" trust "$mac" >/dev/null 2>&1 || true
            "$BT" connect "$mac" >/dev/null 2>&1 || true
          done
          sleep 3
        done
      '';

      # Xbox dongles that boot dead.
      xoneRecover = pkgs.writeShellScript "htpc-xone-recover" ''
        set -u
        # Normal probe finishes first.
        sleep 8
        for try in 1 2 3; do
          fixed=1
          for dev in /sys/bus/usb/devices/*; do
            [ -f "$dev/idVendor" ] && [ -f "$dev/idProduct" ] || continue
            vid=$(cat "$dev/idVendor"); pid=$(cat "$dev/idProduct")
            [ "$vid" = "045e" ] || continue
            case "$pid" in 02fe|0719) ;; *) continue ;; esac
            # Healthy dongles have a driver.
            bound=""
            for intf in "$dev":*/driver; do
              [ -e "$intf" ] || continue
              case "$(basename "$(readlink -f "$intf")")" in
                *xone*|xpad*) bound=1 ;;
              esac
            done
            if [ -z "$bound" ]; then
              echo "xone dongle at $dev unbound — software re-plug (try $try)"
              echo 0 > "$dev/authorized" 2>/dev/null || true
              sleep 2
              echo 1 > "$dev/authorized" 2>/dev/null || true
              fixed=0
            fi
          done
          [ "$fixed" = 1 ] && exit 0
          sleep 5
        done
        exit 0
      '';
    in
    {

      systemd.services.htpc-bt-autopair = {
        description = "Auto-pair any Bluetooth game controller in pairing mode";
        after = [ "bluetooth.service" ];
        wants = [ "bluetooth.service" ];
        wantedBy = [ "bluetooth.target" ];
        serviceConfig = {
          Type = "simple";
          ExecStart = "${btAutopair}";
          Restart = "always";
          RestartSec = 5;
          Nice = 10;
        };
      };

      systemd.services.htpc-xone-recover = {
        description = "Re-plug a dead Xbox Wireless dongle via sysfs";
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${xoneRecover}";
        };
      };

      # Hotplugged dongles too.
      services.udev.extraRules = ''
        ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="045e", ATTR{idProduct}=="02fe", TAG+="systemd", ENV{SYSTEMD_WANTS}+="htpc-xone-recover.service"
        ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="045e", ATTR{idProduct}=="0719", TAG+="systemd", ENV{SYSTEMD_WANTS}+="htpc-xone-recover.service"
      '';
    }
  ;

  # Pads inside the flatpak.
  geforceNow =
    {

      systemd.services.geforce-now-controller-access = {
        description = "Flatpak override: controller access for GeForce NOW";
        wantedBy = [ "multi-user.target" ];
        after = [ "geforce-now-install.service" ];
        path = [ pkgs.flatpak ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          flatpak override --device=all --filesystem=/run/udev:ro com.nvidia.geforcenow
        '';
      };
    };

  # Couch traffic first.
  qos =
    {
      networking.nftables.tables.htpc-qos = {
        family = "inet";
        content = ''
          chain postrouting {
            type filter hook postrouting priority mangle; policy accept;

            # Steam game and voice.
            udp dport 27000-27100 ip dscp set ef
            udp dport 27000-27100 ip6 dscp set ef

            # RetroArch netplay.
            udp dport 55435 ip dscp set ef
            udp dport 55435 ip6 dscp set ef

            # nixlymedia stream, WMM video.
            tcp dport 8080 ip dscp set cs3
            tcp dport 8080 ip6 dscp set cs3
            udp dport 8081 ip dscp set cs3
            udp dport 8081 ip6 dscp set cs3
          }
        '';
      };
    };

  # Small receive queues.
  rxBuffers =
    {
      boot.kernel.sysctl = {
        "net.core.rmem_max" = lib.mkForce 8388608;
        "net.ipv4.tcp_rmem" = lib.mkForce "4096 262144 8388608";
      };
    };

  # Desktop extras off.
  trim =
    {

      # No tablets on a TV.
      hardware.opentabletdriver.enable = lib.mkForce false;
      hardware.opentabletdriver.daemon.enable = lib.mkForce false;

      # No file manager here.
      services.tumbler.enable = lib.mkForce false;

      # Never sleeps mid-stream.
      systemd.targets.sleep.enable = false;
      systemd.targets.suspend.enable = false;
      systemd.targets.hibernate.enable = false;
      systemd.targets.hybrid-sleep.enable = false;
    };

  # Blank keyring under autologin.
  keyring =
    let
      sanitize = pkgs.writeShellScript "nixly-keyring-sanitize" ''
            set -u
            K="$HOME/.local/share/keyrings"
            ${pkgs.coreutils}/bin/mkdir -p "$K"
            ${pkgs.coreutils}/bin/chmod 700 "$K"
            for f in "$K"/*.keyring; do
              [ -f "$f" ] || continue
              if ${pkgs.coreutils}/bin/head -c12 "$f" \
                  | ${pkgs.gnugrep}/bin/grep -q "GnomeKeyring"; then
                ${pkgs.coreutils}/bin/mv "$f" \
                  "$f.locked-$(${pkgs.coreutils}/bin/date +%Y%m%d-%H%M%S)"
              fi
            done
            if [ ! -f "$K/login.keyring" ]; then
              ${pkgs.coreutils}/bin/cat > "$K/login.keyring" <<'EOF'
        [keyring]
        display-name=Login
        ctime=0
        mtime=0
        lock-on-idle=false
        lock-after=false
        EOF
              ${pkgs.coreutils}/bin/chmod 600 "$K/login.keyring"
            fi
      '';
    in
    {
      systemd.user.services.nixly-keyring-sanitize = {
        description = "Blank login keyring so autologin never prompts";
        wantedBy = [ "default.target" ];
        before = [ "gnome-keyring-daemon.service" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${sanitize}";
        };
      };
    }
  ;

in
{
  imports = [
    login
    session
    media
    audio
    hdmiAudio
    biosSync
    retroarch4k
    gpuClocks
    gpuClock
    autoUpdate
    prewarm
    romCache
    controllers
    geforceNow
    qos
    rxBuffers
    trim
    keyring
  ];

  assertions = [{
    assertion = config.nixlyos.mode == "htpc";
    message = "HTPC-modulen hører til profiler med plattform htpc.";
  }];
}
