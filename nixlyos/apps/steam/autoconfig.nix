{ python3, writeScript, gameWrap, protonTool }:

# Runs on the host before every Steam launch, via extraPreBwrapCmds.
# Steam drops keys it did not set on exit, so these settings are reapplied each start.
# Best-effort: failures log to stderr and never block launch.
writeScript "steam-autoconfig" ''
  #!${python3}/bin/python3
  """Steam auto-configuration:
    - proton-nixlyos as the global compat tool AND on every per-app override.
    - Shader pre-caching + background Vulkan shader processing on.
    - Library as start-up location.
    - Friends/news/announcement popups and sounds off.
    - Steam Game Recording off.
    - AutoUpdateBehavior: games 1 (update on launch), Valve tools 2 (high prio).
    - Proton Experimental on the `bleeding-edge` branch.
    - `nixly-game-wrap %command%` on every game's LaunchOptions.
  """
  import glob, os, re, sys, shutil

  # CompatToolMapping needs the tool's internal name from this file; a mismatch
  # silently resolves to no compat tool at all.
  PROTON_VDF = "${protonTool}/bin/compatibilitytool.vdf"

  def find_root():
      xdg = os.environ.get("XDG_DATA_HOME", os.path.expanduser("~/.local/share"))
      for p in [
          os.path.join(xdg, "Steam"),
          os.path.expanduser("~/.steam/steam"),
          os.path.expanduser("~/.steam/root"),
      ]:
          if os.path.isdir(p):
              return p
      return None

  # VDF allows C-style escapes, so the tokenizer consumes `\<anything>` as a unit.
  _UNESC = {"n": "\n", "t": "\t", "r": "\r", "\\": "\\", '"': '"'}

  def _unescape(s):
      return re.sub(r"\\([\s\S])", lambda m: _UNESC.get(m.group(1), m.group(1)), s)

  def _escape(s):
      return (
          s.replace("\\", "\\\\")
           .replace("\"", "\\\"")
           .replace("\n", "\\n")
           .replace("\t", "\\t")
           .replace("\r", "\\r")
      )

  def tokenize(text):
      tokens = []
      for m in re.finditer(r'"((?:[^"\\]|\\[\s\S])*)"|(\{)|(\})', text):
          if m.group(1) is not None:
              tokens.append(("s", _unescape(m.group(1))))
          elif m.group(2):
              tokens.append(("o", "{"))
          else:
              tokens.append(("c", "}"))
      return tokens

  def parse(text):
      toks = tokenize(text)
      result = {}
      stack = [result]
      key = None
      for typ, val in toks:
          if typ == "o":
              d = {}
              if key is not None:
                  stack[-1][key] = d
              stack.append(d)
              key = None
          elif typ == "c":
              stack.pop()
          elif key is None:
              key = val
          else:
              stack[-1][key] = val
              key = None
      return result

  def dump(data, indent=0):
      lines = []
      tab = "\t" * indent
      for k, v in data.items():
          ek = _escape(k)
          if isinstance(v, dict):
              lines.append(f'{tab}"{ek}"')
              lines.append(tab + "{")
              lines.append(dump(v, indent + 1))
              lines.append(tab + "}")
          else:
              lines.append(f'{tab}"{ek}"\t\t"{_escape(str(v))}"')
      return "\n".join(lines)

  def _proton_name():
      try:
          with open(PROTON_VDF) as f:
              tools = parse(f.read())["compatibilitytools"]["compat_tools"]
          for k, v in tools.items():
              if isinstance(v, dict):
                  return k
      except Exception as e:
          print(f"[steam-autoconfig] compat tool name lookup failed: {e}",
                file=sys.stderr)
      return "proton-nixlyos"

  PROTON = _proton_name()

  def ensure(d, keys):
      for k in keys:
          if k not in d or not isinstance(d.get(k), dict):
              d[k] = {}
          d = d[k]
      return d

  def set_leaf(d, key, value):
      if d.get(key) != value:
          d[key] = value
          return True
      return False

  def write_back(path, data):
      backup = path + ".nixly_backup"
      if not os.path.exists(backup):
          shutil.copy2(path, backup)
      with open(path, "w") as f:
          f.write(dump(data))
          f.write("\n")

  def patch_global(path):
      with open(path) as f:
          data = parse(f.read())
      changed = False
      steam_cfg = ensure(data, ["InstallConfigStore", "Software", "Valve", "Steam"])

      # Force every entry onto the proton tool; the "0" wildcard must stay at priority 75,
      # since 250 forces Proton onto Linux-native apps including Steam Linux Runtime.
      compat = ensure(steam_cfg, ["CompatToolMapping"])
      if "0" not in compat or not isinstance(compat.get("0"), dict):
          compat["0"] = {}
      for appid, entry in compat.items():
          if not isinstance(entry, dict):
              continue
          prio = "75" if appid == "0" else "250"
          if entry.get("name") != PROTON or entry.get("priority") != prio:
              entry["name"] = PROTON
              entry["config"] = ""
              entry["priority"] = prio
              changed = True

      # Shader pre-caching and background Vulkan shader processing.
      shader = ensure(steam_cfg, ["ShaderCacheManager"])
      changed |= set_leaf(shader, "EnableShaderBackgroundProcessing", "1")

      if changed:
          write_back(path, data)
          print("[steam-autoconfig] Global config patched.", file=sys.stderr)

  def patch_app_launch_options(user_cfg):
      # Inject `<wrap> %command%` into per-app LaunchOptions for PRIME offload and gamemode.
      wrap = "${gameWrap}"
      new_prefix = f"{wrap} %command%"
      changed = False
      # Steam's case occasionally drifts ("apps" vs "Apps"); check both.
      steam_node = ensure(user_cfg, ["Software", "Valve", "Steam"])
      apps = None
      for k in ("apps", "Apps"):
          v = steam_node.get(k)
          if isinstance(v, dict):
              apps = v
              break
      if apps is None:
          return False

      # Also matches the legacy nixly-gamescope-wrap name so old entries migrate.
      wrap_path_re = re.compile(
          r"/nix/store/[A-Za-z0-9]+-nixly-game(?:scope)?-wrap"
      )

      for appid, app in apps.items():
          if not isinstance(app, dict):
              continue
          opts = app.get("LaunchOptions", "")

          # Already wrapped: only rewrite a drifted store path.
          if wrap_path_re.search(opts):
              new_opts = wrap_path_re.sub(wrap, opts)
              if new_opts != opts:
                  app["LaunchOptions"] = new_opts
                  changed = True
              continue

          if not opts:
              app["LaunchOptions"] = new_prefix
              changed = True
              continue

          # Migrate old `gamemoderun %command%`; the wrap handles gamemode itself now.
          if "gamemoderun %command%" in opts:
              app["LaunchOptions"] = opts.replace(
                  "gamemoderun %command%", new_prefix, 1
              )
              changed = True
              continue

          if "%command%" in opts:
              app["LaunchOptions"] = opts.replace("%command%", new_prefix, 1)
              changed = True
          else:
              # Args-only options: prepend the wrap so the user's args stay intact.
              app["LaunchOptions"] = f"{new_prefix} {opts}"
              changed = True
      return changed

  def patch_localconfig(path):
      with open(path) as f:
          data = parse(f.read())
      changed = False
      user_cfg = ensure(data, ["UserLocalConfigStore"])

      # Friends notifications and sounds off.
      friends = ensure(user_cfg, ["friends"])
      for k in [
          "Notifications_ShowChatRoomNotification",
          "Notifications_ShowMessage",
          "Notifications_ShowOnlineFriend",
          "Notifications_ShowOnlineGame",
          "Notifications_ShowFriendActivity",
          "Notifications_EventsAndAnnouncements",
          "Sounds_PlayChatRoomNotification",
          "Sounds_PlayMessage",
          "Sounds_PlayOnlineFriend",
          "Sounds_PlayOnlineGame",
          "Sounds_PlayEventsAndAnnouncements",
      ]:
          changed |= set_leaf(friends, k, "0")

      # Store and news auto-popups off.
      news = ensure(user_cfg, ["News"])
      changed |= set_leaf(news, "NotifyAvailableGames", "0")

      # Game Recording off; key paths shifted between builds, so write both.
      gr = ensure(user_cfg, ["GameRecording"])
      for k in ("Mode", "Enabled", "BackgroundRecording"):
          changed |= set_leaf(gr, k, "0")
      sv2 = ensure(user_cfg, ["streaming_v2"])
      changed |= set_leaf(sv2, "BackgroundRecording", "0")

      # Per-game PRIME offload + gamemode auto-apply
      changed |= patch_app_launch_options(user_cfg)

      if changed:
          write_back(path, data)
          print(f"[steam-autoconfig] Local UI prefs patched: {path}", file=sys.stderr)

  def patch_sharedconfig(path):
      # Start-up location; the legacy "StartPage" key is dead, SteamDefaultDialog wins.
      with open(path) as f:
          data = parse(f.read())
      steam_cfg = ensure(
          data, ["UserRoamingConfigStore", "Software", "Valve", "Steam"]
      )
      if set_leaf(steam_cfg, "SteamDefaultDialog", "#app_games"):
          write_back(path, data)
          print(f"[steam-autoconfig] Start page set to Library: {path}", file=sys.stderr)

  def library_paths(root):
      # libraryfolders.vdf lives in steamapps/ or, on older clients, config/.
      paths = [root]
      for cand in (
          os.path.join(root, "steamapps", "libraryfolders.vdf"),
          os.path.join(root, "config", "libraryfolders.vdf"),
      ):
          if not os.path.isfile(cand):
              continue
          try:
              with open(cand) as f:
                  data = parse(f.read())
          except Exception:
              continue
          folders = data.get("libraryfolders") or data.get("LibraryFolders") or {}
          if isinstance(folders, dict):
              for v in folders.values():
                  if isinstance(v, dict) and isinstance(v.get("path"), str):
                      paths.append(v["path"])
          break
      # Dedup, preserve order.
      seen, out = set(), []
      for p in paths:
          if p not in seen and os.path.isdir(p):
              seen.add(p)
              out.append(p)
      return out

  # Matched by manifest name so new tools are covered without a hardcoded appid list.
  def is_tool(name):
      return (
          name.startswith("Proton")
          or name.startswith("Steam Linux Runtime")
          or "EasyAntiCheat" in name
          or "BattlEye" in name
      )

  # Beta branch per tool appid.
  TOOL_BETAS = {
      "1493710": "bleeding-edge",   # Proton Experimental
  }

  def patch_appmanifest(path):
      # AutoUpdateBehavior: games get "1" (on launch), Valve tools "2" (high priority).
      with open(path) as f:
          data = parse(f.read())
      appstate = data.get("AppState")
      if not isinstance(appstate, dict):
          return False
      name = appstate.get("name", "")
      appid = appstate.get("appid", "")
      tool = is_tool(name) if isinstance(name, str) else False

      changed = set_leaf(appstate, "AutoUpdateBehavior", "2" if tool else "1")

      beta = TOOL_BETAS.get(appid) if tool else None
      if beta:
          user_cfg = ensure(appstate, ["UserConfig"])
          changed |= set_leaf(user_cfg, "BetaKey", beta)

      if changed:
          write_back(path, data)
      return changed

  def main():
      root = find_root()
      if root is None:
          print(
              "[steam-autoconfig] Steam directory not found. "
              "Settings will be configured after the first Steam launch.",
              file=sys.stderr,
          )
          return

      gconf = os.path.join(root, "config", "config.vdf")
      if os.path.isfile(gconf):
          try:
              patch_global(gconf)
          except Exception as e:
              print(f"[steam-autoconfig] global patch failed: {e}", file=sys.stderr)

      for lc in glob.glob(os.path.join(root, "userdata", "*", "config", "localconfig.vdf")):
          try:
              patch_localconfig(lc)
          except Exception as e:
              print(f"[steam-autoconfig] local patch failed ({lc}): {e}", file=sys.stderr)

      # Roaming store: only exists once the account has logged in at least once.
      for sc in glob.glob(os.path.join(root, "userdata", "*", "7", "remote", "sharedconfig.vdf")):
          try:
              patch_sharedconfig(sc)
          except Exception as e:
              print(f"[steam-autoconfig] roaming patch failed ({sc}): {e}", file=sys.stderr)

      patched = 0
      for lib in library_paths(root):
          for acf in glob.glob(os.path.join(lib, "steamapps", "appmanifest_*.acf")):
              try:
                  if patch_appmanifest(acf):
                      patched += 1
              except Exception as e:
                  print(f"[steam-autoconfig] acf patch failed ({acf}): {e}", file=sys.stderr)
      if patched:
          print(
              f"[steam-autoconfig] Update policy applied to {patched} app(s).",
              file=sys.stderr,
          )

  if __name__ == "__main__":
      main()
''
