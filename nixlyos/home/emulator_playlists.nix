{ config, pkgs, lib, ... }:

# Scans the ROM dirs at activation and writes RetroArch playlists, each pinning a
# default libretro core. Thumbnails are fetched on demand by nixly-fetch-thumbnails,
# and the per-core video settings live in apps/retroarch.nix.

let
  romRoot = "/mnt/nfs/Bigdisk1/Emulator/ROMS";

  # gbSplit: when set, restrict to archives whose first ROM is .gb or .gbc
  systems = [
    { dir = "NES";    dbName = "Nintendo - Nintendo Entertainment System";       coreName = "Nestopia";          exts = [ "nes" "zip" "7z" ];            gbSplit = ""; }
    { dir = "SNES";   dbName = "Nintendo - Super Nintendo Entertainment System"; coreName = "bsnes";             exts = [ "sfc" "smc" "zip" "7z" ];      gbSplit = ""; }
    { dir = "N64";    dbName = "Nintendo - Nintendo 64";                         coreName = "Mupen64Plus-Next";  exts = [ "z64" "n64" "v64" "zip" "7z" ]; gbSplit = ""; }
    { dir = "GBA";    dbName = "Nintendo - Game Boy Advance";                    coreName = "mGBA";              exts = [ "gba" "zip" "7z" ];            gbSplit = ""; }
    { dir = "GB&GBC"; dbName = "Nintendo - Game Boy";                            coreName = "Gambatte";          exts = [ "gb"  "zip" "7z" ];            gbSplit = "gb"; }
    { dir = "GB&GBC"; dbName = "Nintendo - Game Boy Color";                      coreName = "Gambatte";          exts = [ "gbc" "zip" "7z" ];            gbSplit = "gbc"; }
  ];

  systemsJson = pkgs.writeText "emulator-systems.json" (builtins.toJSON systems);

  genScript = pkgs.writeShellApplication {
    name = "nixly-gen-playlists";
    runtimeInputs = with pkgs; [ jq coreutils findutils p7zip unzip gnused gawk gnugrep ];
    text = ''
      set -euo pipefail
      ROM_ROOT="${romRoot}"
      PLAYLIST_DIR="$HOME/.config/retroarch/playlists"
      CACHE_DIR="$HOME/.cache/nixly-emulator/gbsplit"
      mkdir -p "$PLAYLIST_DIR" "$CACHE_DIR"

      sanitize_label() {
        sed -E 's/\.[^.]+$//; s/^[0-9]+ - //; s/ *\([^)]*\)//g; s/ *\[[^]]*\]//g; s/  +/ /g; s/^ +//; s/ +$//' <<<"$1"
      }

      # Peek archive, cache first .gb/.gbc found
      classify_gb_archive() {
        local path="$1" ext="$2"
        local key cache
        key=$(printf '%s' "$path" | sha256sum | cut -d' ' -f1)
        cache="$CACHE_DIR/$key"
        if [[ ! -f "$cache" ]]; then
          local inner=""
          if [[ "$ext" == "7z" ]]; then
            inner=$(7z l -ba -slt "$path" 2>/dev/null \
              | awk -F' = ' '/^Path = /{print tolower($2)}' \
              | grep -oE '\.(gbc|gb)$' | head -1 || true)
          else
            inner=$(unzip -l "$path" 2>/dev/null \
              | awk '{print tolower($NF)}' \
              | grep -oE '\.(gbc|gb)$' | head -1 || true)
          fi
          printf '%s' "$inner" > "$cache"
        fi
        cat "$cache"
      }

      build_playlist() {
        local sys_dir="$1" db_name="$2" core_name="$3" exts="$4" gb_split="$5"
        local src="$ROM_ROOT/$sys_dir"
        if [[ ! -d "$src" ]]; then
          echo "skip $sys_dir (not mounted)"
          return
        fi
        local out="$PLAYLIST_DIR/$db_name.lpl"
        local items_file
        items_file=$(mktemp)

        # Build the -iname chain without a trailing -o.
        local find_args=( "(" )
        local first=1
        for ext in $exts; do
          if [[ $first -eq 0 ]]; then find_args+=( -o ); fi
          find_args+=( -iname "*.$ext" )
          first=0
        done
        find_args+=( ")" )

        local count=0
        while IFS= read -r -d "" path; do
          local base ext_lc label
          base=$(basename "$path")
          ext_lc="''${base##*.}"
          ext_lc="''${ext_lc,,}"

          if [[ -n "$gb_split" ]]; then
            if [[ "$ext_lc" == "7z" || "$ext_lc" == "zip" ]]; then
              local cls
              cls=$(classify_gb_archive "$path" "$ext_lc")
              [[ "$cls" == ".$gb_split" ]] || continue
            elif [[ "$ext_lc" != "$gb_split" ]]; then
              continue
            fi
          fi

          label=$(sanitize_label "$base")
          jq -nc \
            --arg path "$path" \
            --arg label "$label" \
            --arg core "$core_name" \
            --arg db "$db_name.lpl" \
            '{path:$path, label:$label, core_path:"DETECT", core_name:$core, crc32:"DETECT", db_name:$db}' \
            >> "$items_file"
          count=$((count+1))
        done < <(find "$src" -type f \( "''${find_args[@]}" \) -print0)

        jq -n \
          --arg core "$core_name" \
          --slurpfile items "$items_file" \
          '{
             version: "1.5",
             default_core_path: "",
             default_core_name: $core,
             label_display_mode: 0,
             right_thumbnail_mode: 3,
             left_thumbnail_mode: 2,
             thumbnail_match_mode: 0,
             sort_mode: 0,
             scan_content_dir: "",
             scan_file_exts: "",
             scan_dat_file_path: "",
             scan_search_recursively: false,
             scan_search_archives: false,
             scan_filter_dat_content: false,
             scan_overwrite_playlist: false,
             items: ($items[0] // [])
           }' > "$out"
        rm -f "$items_file"
        echo "wrote $out ($count items)"
      }

      jq -c '.[]' ${systemsJson} | while read -r row; do
        dir=$(jq -r '.dir' <<<"$row")
        db=$(jq -r '.dbName' <<<"$row")
        core=$(jq -r '.coreName' <<<"$row")
        exts=$(jq -r '.exts | join(" ")' <<<"$row")
        split=$(jq -r '.gbSplit' <<<"$row")
        build_playlist "$dir" "$db" "$core" "$exts" "$split"
      done
    '';
  };

  fetchScript = pkgs.writeShellApplication {
    name = "nixly-fetch-thumbnails";
    runtimeInputs = with pkgs; [ jq curl coreutils gnused ];
    text = ''
      set -euo pipefail
      THUMB_BASE="https://raw.githubusercontent.com/libretro-thumbnails"
      THUMB_DIR="$HOME/.config/retroarch/thumbnails"
      PLAYLIST_DIR="$HOME/.config/retroarch/playlists"
      mkdir -p "$THUMB_DIR"

      # RetroArch sanitizes these label chars to _
      sanitize() {
        sed -E 's/[&*/:`<>?\\|]/_/g' <<<"$1"
      }

      urlenc() {
        jq -rn --arg s "$1" '$s|@uri'
      }

      shopt -s nullglob
      for lpl in "$PLAYLIST_DIR"/*.lpl; do
        sys=$(basename "$lpl" .lpl)
        repo=''${sys// /_}
        n=$(jq '.items|length' "$lpl")
        echo "==> $sys ($n items)"
        for kind in Named_Boxarts Named_Snaps Named_Titles; do
          mkdir -p "$THUMB_DIR/$sys/$kind"
        done
        while IFS= read -r label; do
          [[ -n "$label" ]] || continue
          clean=$(sanitize "$label")
          enc=$(urlenc "$clean")
          for kind in Named_Boxarts Named_Snaps Named_Titles; do
            dest="$THUMB_DIR/$sys/$kind/$clean.png"
            [[ -f "$dest" ]] && continue
            url="$THUMB_BASE/$repo/master/$kind/$enc.png"
            if curl -fsSL --connect-timeout 5 --max-time 30 -o "$dest.part" "$url" 2>/dev/null; then
              mv "$dest.part" "$dest"
              printf '  ok  %s/%s\n' "$kind" "$clean"
            else
              rm -f "$dest.part"
            fi
          done
        done < <(jq -r '.items[].label' "$lpl")
      done
      echo "Done."
    '';
  };
in
{
  home.packages = [ genScript fetchScript ];

  # mountpoint -q, not [[ -d ]]: testing the automount point triggers the NFS
  # mount, so every rebuild walked the whole ROM library over the network.
  home.activation.emulatorPlaylists = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if ${pkgs.util-linux}/bin/mountpoint -q "/mnt/nfs/Bigdisk1"; then
      $DRY_RUN_CMD ${genScript}/bin/nixly-gen-playlists || true
    else
      echo "ROM root ${romRoot} not mounted, skipping playlist generation"
    fi
  '';
}
