# Cleanup of the old non-Steam shortcuts (RetroArch, nixlymedia,
# GeForce NOW). The apps are launched by the htpc-app supervisor
# (session.nix), so a Big Picture shortcut would just start a second
# instance. htpc-app runs this before every Steam start (Steam only
# reads shortcuts.vdf at startup) so entries written by earlier installs
# get removed too. Idempotent no-op once they're gone.
{ python3, writeScriptBin }:

writeScriptBin "htpc-steam-shortcuts-cleanup" ''
  #!${python3}/bin/python3
  """Remove the old HTPC app shortcuts from every Steam user's shortcuts.vdf."""
  import glob, os, struct, sys

  # Names written by the previous htpc-steam-shortcuts script.
  REMOVE = {"retroarch", "nixlymedia", "geforce now"}

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

  def patch(path):
      if not os.path.exists(path):
          return
      with open(path, "rb") as f:
          raw = f.read()
      try:
          shortcuts = parse(raw).get("shortcuts", {})
      except Exception as e:
          # Unparsable file: not ours to fix — leave it alone.
          print(f"[htpc-steam-shortcuts-cleanup] {path} unparsable ({e}), skipping",
                file=sys.stderr)
          return
      kept = [v for v in shortcuts.values()
              if not (isinstance(v, dict)
                      and v.get("appname", "").lower() in REMOVE)]
      if len(kept) == len(shortcuts):
          return
      # Reindex 0..n-1 the way Steam writes the file itself.
      shortcuts = {str(i): v for i, v in enumerate(kept)}
      blob = b"\x00shortcuts\x00" + dump_obj(shortcuts) + b"\x08"
      tmp = path + ".tmp"
      with open(tmp, "wb") as f:
          f.write(blob)
      os.replace(tmp, path)
      print(f"[htpc-steam-shortcuts-cleanup] removed old shortcuts from {path}",
            file=sys.stderr)

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
                  print(f"[htpc-steam-shortcuts-cleanup] {cfg}: {e}", file=sys.stderr)

  if __name__ == "__main__":
      main()
''
