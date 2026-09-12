# Generator for the HTPC RetroArch playlists: scans the NFS ROM share
# and writes one .lpl playlist per system, every entry pinned to its
# core. Playlist file names are the official RetroArch database names so
# XMB shows the right system icons and thumbnails match up.
# The Switch folder has no libretro core in nixpkgs and is skipped.
{ lib, python3, writeScriptBin, writeText, libretro }:

let
  coreDir = pkg: "${lib.getLib pkg}/lib/retroarch/cores";

  # name = playlist/db name, dir = folder under the ROM root,
  # cores = dir holding the single *_libretro.so, exts = lowercase.
  systems = [
    {
      name = "Nintendo - Nintendo Entertainment System";
      dir = "NES";
      cores = coreDir libretro.nestopia;
      coreName = "Nestopia";
      exts = [ "nes" "fds" "unf" "unif" "zip" "7z" ];
    }
    {
      name = "Nintendo - Super Nintendo Entertainment System";
      dir = "SNES";
      cores = coreDir libretro.snes9x;
      coreName = "Snes9x";
      exts = [ "sfc" "smc" "bs" "zip" "7z" ];
    }
    {
      name = "Nintendo - Game Boy Advance";
      dir = "GBA";
      cores = coreDir libretro.mgba;
      coreName = "mGBA";
      exts = [ "gba" "agb" "zip" "7z" ];
    }
    {
      name = "Nintendo - Game Boy Color";
      dir = "GB&GBC";
      cores = coreDir libretro.gambatte;
      coreName = "Gambatte";
      exts = [ "gb" "gbc" "dmg" "zip" "7z" ];
    }
    {
      name = "Nintendo - Nintendo 64";
      dir = "N64";
      cores = coreDir libretro.mupen64plus;
      coreName = "Mupen64Plus-Next";
      exts = [ "n64" "z64" "v64" "zip" "7z" ];
    }
    {
      name = "Sony - PlayStation 2";
      dir = "PS2";
      cores = coreDir libretro.pcsx2;
      coreName = "PCSX2";
      exts = [ "iso" "chd" "cso" "gz" ];
    }
    {
      name = "Nintendo - GameCube";
      dir = "WII&GC";
      cores = coreDir libretro.dolphin;
      coreName = "Dolphin";
      exts = [ "iso" "gcm" "wbfs" "ciso" "gcz" "rvz" "wia" "7z" ];
    }
  ];

  systemsJson = writeText "htpc-rom-systems.json" (builtins.toJSON systems);
in

writeScriptBin "htpc-rom-playlists" ''
  #!${python3}/bin/python3
  """Scan the NFS ROM share and (re)write the RetroArch playlists."""
  import glob, json, os, sys

  ROMS = "/mnt/nfs/Bigdisk1/Emulator/ROMS"
  OUT = os.path.expanduser("~/.config/retroarch/playlists")
  SYSTEMS = json.load(open("${systemsJson}"))

  def core_so(core_dir):
      hits = sorted(glob.glob(os.path.join(core_dir, "*_libretro.so")))
      return hits[0] if hits else None

  def scan(rom_dir, exts):
      items = []
      for root, _, files in os.walk(rom_dir):
          for f in files:
              ext = os.path.splitext(f)[1].lower().lstrip(".")
              if ext in exts:
                  items.append((os.path.join(root, f),
                                os.path.splitext(f)[0]))
      items.sort(key=lambda i: i[1].lower())
      return items

  def main():
      os.makedirs(OUT, exist_ok=True)
      for s in SYSTEMS:
          rom_dir = os.path.join(ROMS, s["dir"])
          # NFS unreachable or folder renamed: keep whatever playlist we
          # wrote last time instead of clearing the menu.
          if not os.path.isdir(rom_dir):
              print(f"[htpc-rom-playlists] {rom_dir} unavailable, keeping "
                    "existing playlist", file=sys.stderr)
              continue
          core = core_so(s["cores"])
          if not core:
              print(f"[htpc-rom-playlists] no core in {s['cores']}, "
                    f"skipping {s['name']}", file=sys.stderr)
              continue
          db = s["name"] + ".lpl"
          playlist = {
              "version": "1.5",
              "default_core_path": core,
              "default_core_name": s["coreName"],
              "label_display_mode": 0,
              "right_thumbnail_mode": 0,
              "left_thumbnail_mode": 0,
              "sort_mode": 0,
              "items": [{
                  "path": path,
                  "label": label,
                  "core_path": core,
                  "core_name": s["coreName"],
                  "crc32": "00000000|crc",
                  "db_name": db,
              } for path, label in scan(rom_dir, set(s["exts"]))],
          }
          data = json.dumps(playlist, indent=2, ensure_ascii=False)
          out = os.path.join(OUT, db)
          try:
              if open(out, encoding="utf-8").read() == data:
                  continue
          except OSError:
              pass
          tmp = out + ".tmp"
          with open(tmp, "w", encoding="utf-8") as f:
              f.write(data)
          os.replace(tmp, out)
          print(f"[htpc-rom-playlists] wrote {db} "
                f"({len(playlist['items'])} entries)", file=sys.stderr)

  if __name__ == "__main__":
      main()
''
