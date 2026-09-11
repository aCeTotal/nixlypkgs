# Non-Steam shortcuts for Big Picture: RetroArch, nixlymedia and GeForce NOW
# appear as apps in the Steam library, so the couch user switches between
# them with the controller alone. htpc-steam runs this before every Steam
# start (Steam only reads shortcuts.vdf at startup).
{ python3, writeScriptBin }:

writeScriptBin "htpc-steam-shortcuts" ''
  #!${python3}/bin/python3
  """Ensure the HTPC apps exist in every Steam user's shortcuts.vdf."""
  import glob, os, shutil, struct, sys, zlib

  # /run/current-system paths survive updates; store paths would go stale
  # inside shortcuts.vdf after every rebuild.
  APPS = [
      ("RetroArch",   "/run/current-system/sw/bin/retroarch", ""),
      ("nixlymedia",  "/run/current-system/sw/bin/nixlymedia", ""),
      ("GeForce NOW", "/run/current-system/sw/bin/geforce-now", ""),
  ]

  def parse(data):
      """Binary VDF -> dict. Raises on anything malformed."""
      pos = 0
      def read_obj():
          nonlocal pos
          d = {}
          while True:
              t = data[pos]; pos += 1
              if t == 0x08:
                  return d
              end = data.index(b"\x00", pos)
              key = data[pos:end].decode("utf-8", "replace"); pos = end + 1
              if t == 0x00:
                  d[key] = read_obj()
              elif t == 0x01:
                  end = data.index(b"\x00", pos)
                  d[key] = data[pos:end].decode("utf-8", "replace"); pos = end + 1
              elif t == 0x02:
                  d[key] = struct.unpack_from("<i", data, pos)[0]; pos += 4
              else:
                  raise ValueError(f"bad vdf type {t}")
      top = read_obj()
      return top

  def dump_obj(d):
      out = bytearray()
      for k, v in d.items():
          kb = k.encode()
          if isinstance(v, dict):
              out += b"\x00" + kb + b"\x00" + dump_obj(v)
          elif isinstance(v, int):
              out += b"\x02" + kb + b"\x00" + struct.pack("<i", v)
          else:
              out += b"\x01" + kb + b"\x00" + str(v).encode() + b"\x00"
      out += b"\x08"
      return bytes(out)

  def shortcut_appid(exe, name):
      crc = zlib.crc32((exe + name).encode()) | 0x80000000
      return crc - 2**32 if crc >= 2**31 else crc

  def entry(name, exe, opts):
      return {
          "appid": shortcut_appid(f'"{exe}"', name),
          "appname": name,
          "Exe": f'"{exe}"',
          "StartDir": f'"{os.path.expanduser("~")}"',
          "icon": "",
          "ShortcutPath": "",
          "LaunchOptions": opts,
          "IsHidden": 0,
          "AllowDesktopConfig": 1,
          "AllowOverlay": 1,
          "OpenVR": 0,
          "Devkit": 0,
          "DevkitGameID": "",
          "DevkitOverrideAppID": 0,
          "LastPlayTime": 0,
          "FlatpakAppID": "",
          "tags": {},
      }

  def patch(path):
      shortcuts = {}
      if os.path.exists(path):
          with open(path, "rb") as f:
              raw = f.read()
          try:
              shortcuts = parse(raw).get("shortcuts", {})
          except Exception as e:
              # Unreadable file: keep a backup, start fresh.
              print(f"[htpc-steam-shortcuts] {path} unparsable ({e}), rewriting",
                    file=sys.stderr)
              shutil.copy2(path, path + ".nixly_backup")
              shortcuts = {}
      have = {v.get("appname", "").lower()
              for v in shortcuts.values() if isinstance(v, dict)}
      changed = False
      nxt = 0
      for k in shortcuts:
          try:
              nxt = max(nxt, int(k) + 1)
          except ValueError:
              pass
      for name, exe, opts in APPS:
          if name.lower() in have:
              continue
          shortcuts[str(nxt)] = entry(name, exe, opts)
          nxt += 1
          changed = True
      if not changed:
          return
      blob = b"\x00shortcuts\x00" + dump_obj(shortcuts) + b"\x08"
      tmp = path + ".tmp"
      with open(tmp, "wb") as f:
          f.write(blob)
      os.replace(tmp, path)
      print(f"[htpc-steam-shortcuts] patched {path}", file=sys.stderr)

  def main():
      roots = [
          os.path.expanduser("~/.local/share/Steam"),
          os.path.expanduser("~/.steam/steam"),
      ]
      seen = set()
      for root in roots:
          real = os.path.realpath(root)
          if real in seen or not os.path.isdir(real):
              continue
          seen.add(real)
          # One config dir per logged-in Steam account. "0" is the anonymous
          # placeholder Steam sometimes creates — no library, skip it.
          for cfg in glob.glob(os.path.join(real, "userdata", "*", "config")):
              if os.path.basename(os.path.dirname(cfg)) == "0":
                  continue
              try:
                  patch(os.path.join(cfg, "shortcuts.vdf"))
              except Exception as e:
                  print(f"[htpc-steam-shortcuts] {cfg}: {e}", file=sys.stderr)

  if __name__ == "__main__":
      main()
''
