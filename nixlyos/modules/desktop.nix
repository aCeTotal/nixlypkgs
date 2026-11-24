{ config, lib, pkgs, hwData, nixlyUser, ... }:

let
  x86 = hwData.platform.arch == "x86_64";

  # Calculator, PDF and FreeCAD.
  tools =
    { pkgs, lib, ... }:

    let
      freecad = pkgs.freecad.customize {
        modules = [ "${pkgs.freecad-mcp}/share/freecad-mcp/FreeCADMCP" ];
      };
      server = builtins.toJSON {
        type = "stdio";
        command = lib.getExe pkgs.freecad-mcp;
        args = [ ];
      };
    in
    {
      home.packages = [ pkgs.nixly_kalk pkgs.nixly_pdf freecad pkgs.freecad-mcp ];

      # Nixly-PDF opens every PDF.
      xdg.mimeApps = {
        enable = true;
        defaultApplications."application/pdf" = [ "nixly-pdf.desktop" ];
        associations.removed."application/pdf" = [
          "draw.desktop"
          "brave-browser.desktop"
          "com.brave.Browser.desktop"
        ];
      };

      # Merged into mutable ~/.claude.json.
      home.activation.claudeFreecadMcp = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        f="$HOME/.claude.json"
        [ -s "$f" ] || echo '{}' > "$f"
        if ! ${lib.getExe pkgs.jq} -e --argjson s '${server}' '.mcpServers.freecad == $s' "$f" >/dev/null; then
          t=$(mktemp "$f.XXXXXX")
          ${lib.getExe pkgs.jq} --argjson s '${server}' '.mcpServers.freecad = $s' "$f" > "$t"
          mv "$t" "$f"
        fi
      '';
    };

  terrain = { pkgs, ... }: {
    home.packages = [ pkgs.gaea ];
  };

  # Built from the Wayland fork.
  unreal =
    let
      workspace = "/var/cache/ue5";
    in
    {
      options.nixlyos.ue5.enable = lib.mkEnableOption "Unreal Engine 5 built from the Wayland fork";

      config = lib.mkIf config.nixlyos.ue5.enable {
        environment.systemPackages = [ pkgs.ue5_source ];

        # Incremental UBT tree for nixbld.
        nix.settings.extra-sandbox-paths = [ workspace ];
        systemd.tmpfiles.rules = [ "d ${workspace} 2770 root nixbld -" ];
      };
    };

  # The desktop's own cards.
  speakers = {
    xdg.configFile."wireplumber/wireplumber.conf.d/51-audio-priority.conf".text = ''
      monitor.alsa.rules = [
        {
          matches = [
            { device.name = "alsa_card.pci-0000_00_1f.3" }
          ]
          actions = {
            update-props = {
              api.acp.auto-profile = true
              api.acp.auto-port = true
            }
          }
        }
        {
          matches = [
            { device.name = "alsa_card.pci-0000_04_00.0" }
          ]
          actions = {
            update-props = {
              api.acp.auto-profile = false
              device.profile = "output:hdmi-surround71"
            }
          }
        }
        {
          matches = [
            { node.name = "~alsa_output\\.pci-0000_00_1f\\.3\\..*" }
          ]
          actions = {
            update-props = {
              priority.session = 3000
              priority.driver = 3000
            }
          }
        }
        {
          matches = [
            { node.name = "~alsa_output\\.pci-0000_04_00\\.0\\..*" }
          ]
          actions = {
            update-props = {
              priority.session = 2000
              priority.driver = 2000
            }
          }
        }
      ]
    '';
  };

  # HTPC ships its own.
  emulation =
    { pkgs, lib, nixlyUser, ... }:

    {
      environment.systemPackages = with pkgs; [
        # Skips cores ARM lacks.
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

          cores.genesis-plus-gx # Mega Drive / SMS / Game Gear
          cores.gambatte # GB / GBC
          cores.mgba # GBA
          cores.beetle-psx-hw # PlayStation 1 (Vulkan/HW)
        ]))

        retroarch-assets # XMB icons, fonts, menu assets
        retroarch-joypad-autoconfig
      ];

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
          # Monochrome icon pack.
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

          # Per-system XMB wallpapers.
          menu_dynamic_wallpaper_enable = "true"
          dynamic_wallpapers_directory = "${pkgs.retroarch-assets}/share/retroarch/assets/wallpapers"

          # Boxart right, snap left.
          menu_thumbnails = "3"
          menu_left_thumbnails = "2"
          menu_rgui_thumbnail_downscaler = "1"
          playlist_show_sublabels = "true"

          assets_directory = "${pkgs.retroarch-assets}/share/retroarch/assets"
          xmb_font = ""

          # Video
          video_driver = "vulkan"
          video_fullscreen = "true"
          # Covers the layer-shell top.
          video_windowed_fullscreen = "false"
          video_vsync = "true"
          video_threaded = "true"
          video_smooth = "true"
          video_scale_integer = "false"
          video_aspect_ratio_auto = "true"
          # Pure vsync, no VRR.
          video_max_swapchain_images = "3"
          video_frame_delay = "0"
          video_frame_delay_auto = "true"
          video_hard_sync = "false"
          vrr_runloop_enable = "false"
          fastforward_ratio = "0.0"
          video_shader_enable = "true"
          video_shader_dir = "~/.config/retroarch/shaders"

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

          joypad_autoconfig_dir = "${pkgs.retroarch-joypad-autoconfig}/share/libretro/autoconfig"

          # Core / content paths
          libretro_directory = "~/.config/retroarch/cores"
          libretro_info_path = "~/.config/retroarch/cores"
          system_directory = "~/.config/retroarch/system"
          savefile_directory = "~/.config/retroarch/saves"
          savestate_directory = "~/.config/retroarch/states"
          screenshot_directory = "~/.config/retroarch/screenshots"
          playlist_directory = "~/.config/retroarch/playlists"
          thumbnails_directory = "~/.config/retroarch/thumbnails"

          # In-app updater fetches assets.
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

          # Every core fills 16:9.
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

          # Keeps in-app tweaks to other keys.
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

          # Mupen64Plus-Next widescreen hack.
          M64="$RA_CFG_DIR/config/Mupen64Plus-Next/Mupen64Plus-Next.opt"
          upsert_opt "$M64" "mupen64plus-aspect" "16:9 adjusted"
          upsert_opt "$M64" "mupen64plus-169screensize" "1920x1080"
          upsert_opt "$M64" "mupen64plus-parallel-rdp-upscaling" "4x"
          upsert_opt "$M64" "mupen64plus-MultiSampling" "4"
          upsert_opt "$M64" "mupen64plus-Framerate" "Original"

          # ParaLLEl N64 widescreen, 4x.
          PN64="$RA_CFG_DIR/config/ParaLLEl N64/ParaLLEl N64.opt"
          upsert_opt "$PN64" "parallel-n64-aspectratiohint" "widescreen"
          upsert_opt "$PN64" "parallel-n64-screensize" "1920x1080"
          upsert_opt "$PN64" "parallel-n64-parallel-rdp-upscaling" "4x"
          upsert_opt "$PN64" "parallel-n64-framerate" "original"

          # Beetle PSX widescreen, 4x, PGXP.
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

          # bsnes HD Mode 7.
          BSNES="$RA_CFG_DIR/config/bsnes/bsnes.opt"
          upsert_opt "$BSNES" "bsnes_mode7_scale" "8x"
          upsert_opt "$BSNES" "bsnes_mode7_perspective" "ON"
          upsert_opt "$BSNES" "bsnes_mode7_supersample" "ON"
          upsert_opt "$BSNES" "bsnes_mode7_mosaic" "ON"
          upsert_opt "$BSNES" "bsnes_ips_headered" "ON"

          # Needs Update Slang Shaders first.
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
  ;

  citrix =
    let
      icaOpen = pkgs.writeShellApplication {
        name = "nixly-icaopen";
        runtimeInputs = with pkgs; [
          coreutils
          inotify-tools
          systemd
        ];
        text = ''
          mkdir -p "$HOME/Downloads"
          inotifywait -mq -e moved_to -e close_write --format '%w%f' --include '\.ica$' "$HOME/Downloads" |
            while read -r file; do
              systemd-run --user --quiet -- ${pkgs.citrix-workspace-nixly}/bin/wfica "$file"
            done
        '';
      };
    in
    {
      environment.systemPackages = with pkgs; [
        citrix-workspace-nixly
      ];

      # wfica logs nothing without it.
      systemd.user.services.ctxcwalogd = {
        description = "Citrix Workspace log daemon";
        wantedBy = [ "default.target" ];
        serviceConfig = {
          ExecStart = "${pkgs.citrix-workspace-nixly}/opt/citrix-icaclient/util/ctxcwalogd";
          Restart = "on-failure";
        };
      };

      xdg.mime = {
        enable = true;
        addedAssociations."application/x-ica" = "wfica.desktop";
        defaultApplications."application/x-ica" = "wfica.desktop";
      };

      # Citrix owns wfclient.ini.
      home-manager.users.${nixlyUser} = { lib, ... }: {
        # Stale lockdown keys block wfica.
        home.activation.citrixAllRegionsIni = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          SRC="${pkgs.citrix-workspace-nixly}/opt/citrix-icaclient/config/All_Regions.ini"
          DST="$HOME/.ICAClient/All_Regions.ini"
          if [ -f "$DST" ] && ! cmp -s "$SRC" "$DST"; then
            install -m 600 "$SRC" "$DST"
          fi
        '';

        home.activation.citrixWfclientIni = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          INI="$HOME/.ICAClient/wfclient.ini"
          if [ -f "$INI" ]; then
            # Default fullscreen spans every monitor.
            ${pkgs.gnused}/bin/sed -i \
              's/^UseFullScreen[[:space:]]*=.*/UseFullScreen=False/' "$INI"

            # Read-write home drive, local Super.
            for kv in CDMAllowed=True DriveEnabledA=True 'DrivePathA=$HOME' \
                DriveReadAccessA=0 DriveWriteAccessA=0 SuperMetaToWinKeys=False; do
              key=''${kv%%=*}
              if ${pkgs.gnugrep}/bin/grep -q "^$key[[:space:]]*=" "$INI"; then
                ${pkgs.gnused}/bin/sed -i "s|^$key[[:space:]]*=.*|$kv|" "$INI"
              else
                ${pkgs.gnused}/bin/sed -i "/^\[WFClient\]/a $kv" "$INI"
              fi
            done
          fi
        '';
      };

      # Opens outside the jail.
      systemd.user.services.nixly-icaopen = {
        description = "Open downloaded Citrix launch files";
        partOf = [ "graphical-session.target" ];
        after = [ "graphical-session.target" ];
        wantedBy = [ "graphical-session.target" ];
        serviceConfig = {
          ExecStart = "${icaOpen}/bin/nixly-icaopen";
          Restart = "on-failure";
          RestartSec = 3;
        };
      };
    };

  claudeCode =
    let
      card = pkgs.writeShellApplication {
        name = "claude-thumb-card";
        runtimeInputs = with pkgs; [ libnotify swayimg ];
        text = ''
          action=$(notify-send --app-name=Claude --expire-time=8000 \
            --hint="string:image-path:$1" --action=default=Open --wait \
            "$(basename "$1")")
          if [ "$action" = default ]; then
            exec swayimg "$1"
          fi
        '';
      };

      # Viewer escapes the idle hook.
      hook = pkgs.writeShellApplication {
        name = "claude-thumb";
        runtimeInputs = with pkgs; [ jq util-linux ];
        text = ''
          f=$(jq -r '.tool_input.file_path // empty')
          case "''${f,,}" in
            *.png | *.jpg | *.jpeg | *.webp | *.gif | *.bmp) ;;
            *) exit 0 ;;
          esac
          if [ -f "$f" ]; then
            setsid -f chrt --other 0 ${card}/bin/claude-thumb-card "$f" >/dev/null 2>&1
          fi
        '';
      };

      cli = { pkgs, ... }: {
        home.packages = [ pkgs.claude pkgs.meshy ];
        home.file.".claude/skills/meshy/SKILL.md".source = "${pkgs.meshy}/share/meshy/SKILL.md";
        programs.bash.shellAliases.c = "claude --dangerously-skip-permissions";
      };

      code =
        { lib, ... }:

        {
          home.activation.removeStaleClaudeMd = lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
            if [ -e "$HOME/.claude/CLAUDE.md" ] && [ ! -L "$HOME/.claude/CLAUDE.md" ]; then
              rm -f "$HOME/.claude/CLAUDE.md"
            fi
          '';

          home.file.".claude/CLAUDE.md".text = ''
            1. Think Before Coding

            Don't assume. Don't hide confusion. Surface tradeoffs.

            Before implementing:

            State your assumptions explicitly. If uncertain, ask.
            If multiple interpretations exist, present them - don't pick silently.
            If a simpler approach exists, say so. Push back when warranted.
            If something is unclear, stop. Name what's confusing. Ask.
            2. Simplicity First

            Minimum code that solves the problem. Nothing speculative.

            No features beyond what was asked.
            No abstractions for single-use code.
            No "flexibility" or "configurability" that wasn't requested.
            No error handling for impossible scenarios.
            If you write 200 lines and it could be 50, rewrite it.
            Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

            3. Surgical Changes

            Touch only what you must. Clean up only your own mess.

            When editing existing code:

            Don't "improve" adjacent code, comments, or formatting.
            Don't refactor things that aren't broken.
            Match existing style, even if you'd do it differently.
            If you notice unrelated dead code, mention it - don't delete it.
            When your changes create orphans:

            Remove imports/variables/functions that YOUR changes made unused.
            Don't remove pre-existing dead code unless asked.
            The test: Every changed line should trace directly to the user's request.

            4. Goal-Driven Execution

            Define success criteria. Loop until verified.

            Transform tasks into verifiable goals:

            "Add validation" → "Write tests for invalid inputs, then make them pass"
            "Fix the bug" → "Write a test that reproduces it, then make it pass"
            "Refactor X" → "Ensure tests pass before and after"
            For multi-step tasks, state a brief plan:

            1. [Step] → verify: [check]
            2. [Step] → verify: [check]
            3. [Step] → verify: [check]
            Strong success criteria let you loop independently. Weak criteria ("make it work") require constant clarification.

            5. Never commit or push changes.

            6. File and Folder Organization

            One thing per file. Short, descriptive names. Related files grouped in short, descriptive folders.

            A file is named after the one thing it contains. No plural dumping grounds.
            No file named utils, helpers, common, misc, core, shared, lib, or stuff.
            No file over ~300 lines. If it grew past that, it holds more than one thing.
            Folder depth stays shallow - three levels from the repo root is the normal maximum.
            Folders group by feature, not by file type. Not controllers/models/views.
            A folder with one file is not a folder. A folder with twenty files is two folders.
            Name files after what they are, not when they arrived: no new, old, tmp, backup, v2, final.

            7. Comments

            Max one comment per thing. One sentence, max 5 descriptive words.
            This applies everywhere, including existing files: when touching code with longer comments, shorten them to fit this rule. This overrides "match existing style" for comments.

            8. Database Work

            All database work is done cleanly and professionally.

            No database may have artificial limitations or bottlenecks.
            Index what is queried. No N+1 queries, no unbounded scans.
            Schema changes go through proper migrations.

            9. Nix Projects

            Every nix project ships a flake:

            "nix develop" provides everything the project needs.
            "nix run" always runs the project.
            If servers are involved, they start automatically first — then the program or website pops up on its own.

            10. Performance

            Only highly efficient code, optimized for best possible performance.

            Never take the shortest path to a result — take the optimized path, with clean and efficient code.
            Prefer the least code that achieves it.

            11. Look and Feel

            Everything user-facing must look modern and professional, with tasteful eye-candy.

            12. Hash Updates (nixlypkgs)

            When asked to refresh a derivation hash, do it lightning-fast: fetch new hash, update rev/hash, done. No analysis, no questions, no extra reading.

            13. No AI Fingerprints

            Code must read like one experienced human wrote it.

            Never: banner comments, emoji, decorative separators, section headers inside code.
            Never: comments restating the line below, docstrings on obvious functions, "Note that", "This ensures that".
            Never: leftover placeholders, "rest of code unchanged", commented-out old code beside new code.
            Never: symmetric boilerplate applied everywhere - try/catch around every call, {ok, error} on every return, null checks for values that cannot be null.
            Never: names like data, result, temp, info, helper, manager, handler, utils, processX, doX, enhanced, improved, v2.
            Never: a summary paragraph at the top of a file restating what the file does.
            Never: duplicated near-identical blocks that should be a loop or a table.
            If a reviewer could name the tool that wrote it, rewrite it.

            14. Control Flow

            Flat beats nested. Always.

            No nested if statements. Invert the condition and return early.
            Max two levels of indentation inside a function body. Three means a function is missing.
            No else after return, break, or continue.
            No if/else chain longer than three arms - use a table, map, or switch on an enum.
            No boolean parameter that selects behaviour - write two functions.
            Handle the error case first; the happy path runs unindented to the end.
            No nested loops that could be hoisted, flattened, or indexed.

            15. Function and Data Shape

            One function, one job, one level of abstraction.

            A function fits on one screen. If it does not, it is doing two things.
            Three arguments or fewer. More means a struct is missing.
            One way out: no out-parameters mixed with return values.
            No stringly-typed state - enums or tagged unions.
            No magic numbers or magic strings - named constants.
            Validate at the boundary, trust inside it. No re-checking downstream.
            Plain data plus functions beats a class that exists to hold one value.

            16. Optimized Means Measured

            "Optimized" is a claim, and claims need evidence.

            Name the hot path before optimizing it.
            Allocate outside the loop, never inside. Compute invariants once.
            Contiguous arrays over pointer chasing; indices over pointers when data can move.
            No hidden work: no accidental copy, no formatting in a hot loop, no syscall per iteration.
            Right algorithm first, micro-optimization after.
            If the faster version is uglier with no measured win, keep the clear one.

            17. Definition of Done

            Done means a top-tier engineer finds nothing to change.

            Builds clean with all warnings enabled. Zero warnings, zero suppressions.
            No dead code, unused arguments, or unused imports left by your change.
            No TODO, FIXME, or stub that you introduced.
            Every line justifies itself. Delete what you cannot defend.
            Re-read the whole diff as a reviewer before reporting done. If you would comment on it, fix it first.
            Taking longer is fine. Shipping work that needs a second pass is not.

            18. Project Structure

            An experienced developer opens the repo and knows where everything is in thirty seconds.

            The root holds only what must be there: README, flake.nix, and the top-level source folders. Nothing else.
            No stray scripts, notes, logs, backups, or scratch files anywhere in the tree. Those live outside the repo.
            Every folder name says what lives in it. If you need a comment to explain the layout, the layout is wrong.
            Structure mirrors the domain, so the folder tree reads as the feature list.
            One obvious place for each kind of thing, and only one. No parallel half-migrated layouts.
            Entry points are obvious and few: one way to build, one way to run, one way to test.
            Generated and vendored output never mixes with source, and is gitignored.
            README is short: what it is, how to run it, how the tree is laid out. Nothing that will rot.
            Before finishing a task, look at the tree you leave behind. If a new developer would ask "why is this here?", move it or delete it.

            19. Gitignore

            Every project ships a .gitignore at the repo root. Only source belongs in git.

            Create it in the first commit of a new project. If a project lacks one, add it before anything else.
            Ignore all agent and LLM artifacts: .claude/, .cursor/, .aider*, .continue/, .windsurf/, .codeium/, .github/copilot*, *.agent.md, chat and session logs, plan/summary/analysis notes, and any scratch file an assistant produced.
            Ignore build output, generated code, and vendored dependencies: result, result-*, build/, dist/, target/, node_modules/, .venv/, __pycache__/, *.o, *.so.
            Ignore secrets and local config: .env, .env.*, *.key, *.pem, *.local, local settings files.
            Ignore editor and OS junk: .idea/, .vscode/, *.swp, .DS_Store, Thumbs.db.
            Ignore caches and logs: .cache/, *.log, coverage/, .direnv/.
            Keep it curated and short: entries for what this project actually produces, not a copied 300-line template. No blanket wildcards that hide real source.
            Never commit a file the .gitignore is meant to catch, and never force-add one.
            A tracked file that should be ignored is a bug: say so, and fix the ignore rule.

            20. 3D Assets

            Meshes, props, characters and animations come from the `meshy` CLI (skill: meshy), never hand-built geometry or placeholder shapes when a real asset is wanted.
            Load the meshy skill before touching 3D assets in a Bevy project.
          '';
        }
      ;

      caveman =
        { config, pkgs, lib, ... }:

        let
          caveman-src = pkgs.fetchFromGitHub {
            owner = "JuliusBrussee";
            repo = "caveman";
            rev = "600e8efcd6aca4006051ca2a889aa8100a9b3967";
            hash = "sha256-gDPgQx1TIhGrJ2EVvEoDY+4MXdlI79zdcx6pL5nMEG4=";
          };
        in
        {
          home.packages = [ pkgs.nodejs ];

          home.file = {
            # Node resolves symlinks to store.
            ".claude/hooks/caveman-config.js".source = "${caveman-src}/hooks/caveman-config.js";
            ".claude/hooks/caveman-activate.js".source = "${caveman-src}/hooks/caveman-activate.js";
            ".claude/hooks/caveman-mode-tracker.js".source = "${caveman-src}/hooks/caveman-mode-tracker.js";
            ".claude/hooks/caveman-statusline.sh" = {
              source = "${caveman-src}/hooks/caveman-statusline.sh";
              executable = true;
            };

            # Slash commands
            ".claude/commands/caveman.toml".source = "${caveman-src}/commands/caveman.toml";
            ".claude/commands/caveman-commit.toml".source = "${caveman-src}/commands/caveman-commit.toml";
            ".claude/commands/caveman-review.toml".source = "${caveman-src}/commands/caveman-review.toml";
          };

          # Merged into mutable settings.json.
          home.activation.setupCavemanHooks = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
                SETTINGS="$HOME/.claude/settings.json"
                mkdir -p "$HOME/.claude"

                if [ ! -f "$SETTINGS" ]; then
                  echo '{}' > "$SETTINGS"
                fi

                ${pkgs.nodejs}/bin/node - "$SETTINGS" << 'NODEOF'
            const fs = require("fs");
            const settingsPath = process.argv[2];

            let settings = {};
            try { settings = JSON.parse(fs.readFileSync(settingsPath, "utf8")); } catch {}

            if (!settings.hooks) settings.hooks = {};
            if (!Array.isArray(settings.hooks.SessionStart)) settings.hooks.SessionStart = [];
            if (!Array.isArray(settings.hooks.UserPromptSubmit)) settings.hooks.UserPromptSubmit = [];

            // Drop old caveman hooks.
            const notCaveman = (e) =>
              !(e.hooks && e.hooks.some((h) => h.command && h.command.includes("caveman")));

            settings.hooks.SessionStart = settings.hooks.SessionStart.filter(notCaveman);
            settings.hooks.UserPromptSubmit = settings.hooks.UserPromptSubmit.filter(notCaveman);

            settings.hooks.SessionStart.push({
              hooks: [
                {
                  type: "command",
                  command: "node $HOME/.claude/hooks/caveman-activate.js",
                  timeout: 5000,
                },
              ],
            });

            settings.hooks.UserPromptSubmit.push({
              hooks: [
                {
                  type: "command",
                  command: "node $HOME/.claude/hooks/caveman-mode-tracker.js",
                  timeout: 5000,
                },
              ],
            });

            fs.writeFileSync(settingsPath, JSON.stringify(settings, null, 2) + "\n");
            NODEOF
          '';
        }
      ;
    in
    {
      # Image reads become notification cards.
      environment.etc."claude-code/managed-settings.json".text = builtins.toJSON {
        hooks.PostToolUse = [
          {
            matcher = "Read";
            hooks = [
              {
                type = "command";
                command = "${hook}/bin/claude-thumb";
              }
            ];
          }
        ];
      };

      home-manager.sharedModules = [ cli code caveman ];
    };

  blenderSetup =
    { config, pkgs, lib, ... }:

    let
      cfg = config.nixly.blender;

      # Official LTS has every kernel.
      blenderPkg = pkgs.Blender_bin_lts;

      blenderBin = lib.getExe blenderPkg;

      # Best backend per vendor.
      cyclesDevice = {
        nvidia = "OPTIX";
        amd = "HIP";
        intel = "ONEAPI";
      }.${cfg.variant};

      acceptedDeviceTypes = {
        nvidia = [ "OPTIX" "CUDA" ];
        amd = [ "HIP" ];
        intel = [ "ONEAPI" ];
      }.${cfg.variant};

      # Bundled with Blender under legacy module IDs.
      bundledAddons = [ "node_wrangler" "rigify" ];

      # Typo "objectes" is upstream's.
      extensionAddons = [
        "looptools"
        "f2"
        "auto_mirror"
        "copy_attributes_menu"
        "bool_tool"
        "extra_mesh_objects"
        "extra_curve_objectes"
      ];

      # Bump URL and hash together.
      fetchExt = url: sha256: pkgs.fetchurl { inherit url sha256; };
      extZips = {
        looptools = fetchExt
          "https://extensions.blender.org/download/sha256:ff1ca3b3fff73094379da8b1fa2c1acbc9d88d26b7dfc73bb9de5941a6b50108/add-on-looptools-v4.7.7.zip"
          "ff1ca3b3fff73094379da8b1fa2c1acbc9d88d26b7dfc73bb9de5941a6b50108";
        f2 = fetchExt
          "https://extensions.blender.org/download/sha256:dc8f19637a61c332b3eb937a6b86e2363511cbb29a9a22ea8571fe7d924ab05c/add-on-f2-v1.8.5.zip"
          "dc8f19637a61c332b3eb937a6b86e2363511cbb29a9a22ea8571fe7d924ab05c";
        auto_mirror = fetchExt
          "https://extensions.blender.org/download/sha256:68c7785f641c91905b07b8122af6a0147834e9a7b77285966253b1f770f30cc7/add-on-auto-mirror-v2.5.4.zip"
          "68c7785f641c91905b07b8122af6a0147834e9a7b77285966253b1f770f30cc7";
        copy_attributes_menu = fetchExt
          "https://extensions.blender.org/download/sha256:990bac36be4c6a39c4506c84a689c5ec45e1a4b43995542cd0b058663f190478/add-on-copy-attributes-menu-v0.6.3.zip"
          "990bac36be4c6a39c4506c84a689c5ec45e1a4b43995542cd0b058663f190478";
        bool_tool = fetchExt
          "https://extensions.blender.org/download/sha256:9d9c73f2f49af05e3a3cfe78daa43676b1005fcbb591dc054d9d04c370f0d85d/add-on-bool-tool-v2.0.0.zip"
          "9d9c73f2f49af05e3a3cfe78daa43676b1005fcbb591dc054d9d04c370f0d85d";
        extra_mesh_objects = fetchExt
          "https://extensions.blender.org/download/sha256:c85ce4bb2820d5af26b4dad66bf1a0fdeb4bfeffc668c5e4f098f1e416ed434b/add-on-extra-mesh-objects-v0.4.1.zip"
          "c85ce4bb2820d5af26b4dad66bf1a0fdeb4bfeffc668c5e4f098f1e416ed434b";
        extra_curve_objectes = fetchExt
          "https://extensions.blender.org/download/sha256:4ca91ce5563d094694b2c7f1fc9acece8b5ba8f5dd017a49f080e9cfa5553909/add-on-extra-curve-objectes-v0.2.0.zip"
          "4ca91ce5563d094694b2c7f1fc9acece8b5ba8f5dd017a49f080e9cfa5553909";
      };
      extZipPaths = lib.mapAttrsToList (_: zip: "${zip}") extZips;

      # GitHub source as legacy addon.
      blenderkitSrc = pkgs.fetchFromGitHub {
        owner = "BlenderKit";
        repo = "BlenderKit";
        rev = "5d252bee50bef7e409caad047432c028c28e10fa";
        hash = "sha256-QIwMDN4B3XDoi+OMnuURpRv/1bs7bzfBRbsdRBFNe3Y=";
      };

      setupPy = pkgs.writeText "blender-setup.py" ''
        import bpy, addon_utils

        bundled         = ${builtins.toJSON bundledAddons}
        extension_ids   = ${builtins.toJSON extensionAddons}
        extension_zips  = ${builtins.toJSON extZipPaths}
        accepted_devs   = ${builtins.toJSON acceptedDeviceTypes}
        cycles_dev_type = "${cyclesDevice}"

        def safe(label, fn):
            try: fn()
            except Exception as e: print(f"[setup] {label}: {e}")

        # Install pinned extensions from local zips.
        for z in extension_zips:
            safe(f"install {z}", lambda z=z: bpy.ops.extensions.package_install_files(
                filepath=z, repo="user_default", enable_on_install=True))

        # Enable bundled addons and BlenderKit.
        for a in bundled + ["blenderkit"]:
            safe(f"enable {a}", lambda a=a:
                addon_utils.enable(a, default_set=True, persistent=True))

        # enable_on_install misses some.
        for ext in extension_ids:
            mod = f"bl_ext.user_default.{ext}"
            safe(f"enable ext {ext}", lambda mod=mod:
                bpy.ops.preferences.addon_enable(module=mod))

        # Cycles compute device.
        def setup_cycles():
            cprefs = bpy.context.preferences.addons["cycles"].preferences
            cprefs.compute_device_type = cycles_dev_type
            cprefs.refresh_devices()
            for d in cprefs.devices:
                d.use = d.type in accepted_devs
        safe("cycles devices", setup_cycles)

        # System and performance
        sysprefs = bpy.context.preferences.system
        safe("gpu_backend",       lambda: setattr(sysprefs, "gpu_backend", "VULKAN"))
        safe("memory_cache",      lambda: setattr(sysprefs, "memory_cache_limit", 8192))
        safe("gpu_subdivision",   lambda: setattr(sysprefs, "use_gpu_subdivision", True))

        # Edit and undo
        edit = bpy.context.preferences.edit
        edit.undo_steps = 256
        edit.undo_memory_limit = 1024

        # Input
        inp = bpy.context.preferences.inputs
        inp.view_rotate_method            = "TURNTABLE"
        inp.use_zoom_to_mouse             = True
        inp.use_rotate_around_active      = True   # Orbit Around Selection
        inp.use_auto_depth                = True   # Auto Depth (under Orbit Around Selection)
        inp.use_mouse_emulate_3_button    = True
        inp.mouse_emulate_3_button_modifier = "ALT"
        safe("tablet_api", lambda: setattr(inp, "tablet_api", "AUTOMATIC"))

        # View and UI
        bpy.context.preferences.view.ui_scale = 1.5

        # Save
        bpy.ops.wm.save_userpref()
        print("[setup] complete")
      '';
    in
    {
      options.nixly.blender = {
        variant = lib.mkOption {
          type = lib.types.enum [ "nvidia" "amd" "intel" ];
          default = "nvidia";
          description = "Blender GPU variant — picks Cycles backend + auto-enabled compute device";
        };
      };

      config = {
        home.packages = [ blenderPkg ];

        home.file.".config/blender/5.2/scripts/addons/blenderkit".source = blenderkitSrc;

        # Delete the flag to rerun.
        home.activation.blenderSetup = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          FLAG="$HOME/.config/blender/.nix_setup_v2"
          if [ ! -f "$FLAG" ] && [ -x "${blenderBin}" ]; then
            echo "[blender] bootstrapping addons + prefs (one-time)..."
            mkdir -p "$HOME/.config/blender"
            if "${blenderBin}" --background --python "${setupPy}"; then
              touch "$FLAG"
              echo "[blender] setup complete"
            else
              echo "[blender] setup failed; will retry on next HM rebuild"
            fi
          fi
        '';
      };
    }
  ;

  blender = {
    home-manager.sharedModules = [ blenderSetup ];
  };
in
{
  imports = [ emulation claudeCode ] ++ lib.optionals x86 [ unreal citrix blender ];

  assertions = [{
    assertion = config.nixlyos.mode == "desktop";
    message = "Desktop-modulen hører til profiler med plattform desktop.";
  }];

  home-manager.sharedModules = [ tools speakers ] ++ lib.optional x86 terrain;
}
