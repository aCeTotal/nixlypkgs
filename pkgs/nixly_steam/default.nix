{
  lib,
  stdenvNoCC,
  makeWrapper,
  writeScript,
  steam,
  python3,
  bash,
  bubblewrap,
  proton-ge-bin,
  proton-cachyos,
  # Extra CLI args appended to the steam invocation. Default disables CEF GPU
  # compositing — required under Niri/xwayland-satellite where rootless
  # XWayland breaks CEF compositing → Steam UI black window.
  extraSteamArgs ? [ "-cef-disable-gpu-compositing" ],
  # Compat tools exposed via STEAM_EXTRA_COMPAT_TOOLS_PATHS. programs.steam's
  # extraCompatPackages only wires the system steam binary (it's a
  # configuration on programs.steam.package, not a global env injection).
  # nixly_steam exec's `steam` from its own PATH and never inherits that.
  # Bake the path into the launcher so GE-Proton + Proton CachyOS appear in
  # Steam's compat-tool dropdown when launched via nixly_steam.
  extraCompatPackages ? [ proton-ge-bin proton-cachyos ],
}:

let
  configureProton = writeScript "nixly-steam-configure-proton" ''
    #!${python3}/bin/python3
    """Auto-configure Steam: Proton CachyOS default, shader pre-cache,
    Library as start page, friends + news popups off, gamemoderun prefix
    on every game's LaunchOptions.

    Steam rewrites localconfig.vdf on exit, so this runs on every launch.
    Best-effort: VDF key names occasionally shift between Steam UI rewrites.
    """
    import glob, os, re, sys, shutil

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

    def tokenize(text):
        tokens = []
        for m in re.finditer(r'"([^"]*)"|(\{)|(\})', text):
            if m.group(1) is not None:
                tokens.append(("s", m.group(1)))
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
            if isinstance(v, dict):
                lines.append(f'{tab}"{k}"')
                lines.append(tab + "{")
                lines.append(dump(v, indent + 1))
                lines.append(tab + "}")
            else:
                lines.append(f'{tab}"{k}"\t\t"{v}"')
        return "\n".join(lines)

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

        # Global default: Proton CachyOS
        compat = ensure(steam_cfg, ["CompatToolMapping"])
        if "0" not in compat or not isinstance(compat.get("0"), dict):
            compat["0"] = {}
        entry = compat["0"]
        if entry.get("name") != "Proton CachyOS":
            entry["name"] = "Proton CachyOS"
            entry["config"] = ""
            entry["priority"] = "250"
            changed = True

        # Shader Pre-Caching & background Vulkan shader processing
        shader = ensure(steam_cfg, ["ShaderCacheManager"])
        changed |= set_leaf(shader, "EnableShaderBackgroundProcessing", "1")

        # Library as start page (global fallback)
        changed |= set_leaf(steam_cfg, "StartPage", "Library")

        if changed:
            write_back(path, data)
            print("[nixly_steam] Global config patched.", file=sys.stderr)

    def patch_app_launch_options(user_cfg):
        # Inject `gamemoderun %command%` into per-app LaunchOptions so every
        # game runs under gamemode without wrapping Steam itself. Re-runs on
        # each Steam start, so newly installed games get covered.
        prefix = "gamemoderun %command%"
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

        for appid, app in apps.items():
            if not isinstance(app, dict):
                continue
            opts = app.get("LaunchOptions", "")
            if "gamemoderun" in opts:
                continue
            if not opts:
                app["LaunchOptions"] = prefix
                changed = True
            elif "%command%" in opts:
                app["LaunchOptions"] = opts.replace(
                    "%command%", "gamemoderun %command%", 1
                )
                changed = True
            else:
                # Args-only launch options: prepending would make Steam launch
                # `gamemoderun` as the game binary. Skip to avoid breakage.
                print(
                    f"[nixly_steam] app {appid}: args-only LaunchOptions "
                    f"({opts!r}); skipping gamemode prefix.",
                    file=sys.stderr,
                )
        return changed

    def patch_localconfig(path):
        with open(path) as f:
            data = parse(f.read())
        changed = False
        user_cfg = ensure(data, ["UserLocalConfigStore"])

        # Library as start page (per-user; Steam reads this over global)
        system = ensure(user_cfg, ["system"])
        changed |= set_leaf(system, "StartPage", "Library")

        # Friends notifications + sounds off (no chat/online popups)
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

        # News popups off (store/news auto-popups)
        news = ensure(user_cfg, ["News"])
        changed |= set_leaf(news, "NotifyAvailableGames", "0")

        # Steam Game Recording off — background recording eats CPU/disk
        # constantly during gameplay. Key paths shifted between Steam builds
        # (streaming_v2 vs GameRecording subtree); write to all known
        # locations. Best-effort: extra keys are harmless if Steam ignores.
        gr = ensure(user_cfg, ["GameRecording"])
        for k in ("Mode", "Enabled", "BackgroundRecording"):
            changed |= set_leaf(gr, k, "0")
        sv2 = ensure(user_cfg, ["streaming_v2"])
        changed |= set_leaf(sv2, "BackgroundRecording", "0")

        # Per-game gamemode auto-apply
        changed |= patch_app_launch_options(user_cfg)

        if changed:
            write_back(path, data)
            print(f"[nixly_steam] Local UI prefs patched: {path}", file=sys.stderr)

    def library_paths(root):
        # libraryfolders.vdf lives in steamapps/ (current) or config/ (older).
        # Returns list of library root dirs (each contains steamapps/).
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

    def patch_appmanifest(path):
        # AutoUpdateBehavior: "0" always-update (default), "1" only-on-launch,
        # "2" high-priority. Set to "1" so background updates don't hit disk
        # /bandwidth during gameplay. New installs get "0" → re-run on each
        # launch.
        with open(path) as f:
            data = parse(f.read())
        appstate = data.get("AppState")
        if not isinstance(appstate, dict):
            return False
        if appstate.get("AutoUpdateBehavior") == "1":
            return False
        appstate["AutoUpdateBehavior"] = "1"
        write_back(path, data)
        return True

    def main():
        root = find_root()
        if root is None:
            print(
                "[nixly_steam] Steam directory not found. "
                "Settings will be configured after first Steam launch.",
                file=sys.stderr,
            )
            return

        gconf = os.path.join(root, "config", "config.vdf")
        if os.path.isfile(gconf):
            try:
                patch_global(gconf)
            except Exception as e:
                print(f"[nixly_steam] global patch failed: {e}", file=sys.stderr)

        for lc in glob.glob(os.path.join(root, "userdata", "*", "config", "localconfig.vdf")):
            try:
                patch_localconfig(lc)
            except Exception as e:
                print(f"[nixly_steam] local patch failed ({lc}): {e}", file=sys.stderr)

        patched = 0
        for lib in library_paths(root):
            for acf in glob.glob(os.path.join(lib, "steamapps", "appmanifest_*.acf")):
                try:
                    if patch_appmanifest(acf):
                        patched += 1
                except Exception as e:
                    print(f"[nixly_steam] acf patch failed ({acf}): {e}", file=sys.stderr)
        if patched:
            print(
                f"[nixly_steam] AutoUpdateBehavior=1 applied to {patched} app(s).",
                file=sys.stderr,
            )

    if __name__ == "__main__":
        main()
  '';

in

stdenvNoCC.mkDerivation {
  pname = "nixly_steam";
  version = "1.1.0.0";

  dontUnpack = true;
  dontBuild = true;

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin $out/share/applications

    cat > $out/bin/nixly_steam <<'LAUNCHER'
#!/usr/bin/env bash
set -euo pipefail

# Use nix store bubblewrap to avoid "Unexpected capabilities but not setuid" error.
# The store binary has no file capabilities, so pressure-vessel works cleanly.
export PRESSURE_VESSEL_BWRAP="NIXLY_BWRAP_PATH"
export PRESSURE_VESSEL_FILESYSTEMS_RO=/nix/store

# Vendor-agnostic gaming env: each var is consumed only by matching driver
# (RADV_* = AMD mesa; __GL_* = NVIDIA proprietary; mesa_glthread = mesa).
# All no-op on non-matching hardware. Safe across Intel/AMD/NVIDIA.
export RADV_PERFTEST="''${RADV_PERFTEST:-gpl,nggc}"
export mesa_glthread="''${mesa_glthread:-true}"
export MESA_SHADER_CACHE_MAX_SIZE="''${MESA_SHADER_CACHE_MAX_SIZE:-10G}"
export __GL_THREADED_OPTIMIZATIONS="''${__GL_THREADED_OPTIMIZATIONS:-1}"
export __GL_SHADER_DISK_CACHE_SIZE="''${__GL_SHADER_DISK_CACHE_SIZE:-10737418240}"

# Proton/DXVK/VKD3D — DLSS/Reflex/DXR enablement. Vendor-agnostic.
export PROTON_ENABLE_NVAPI="''${PROTON_ENABLE_NVAPI:-1}"
export DXVK_ENABLE_NVAPI="''${DXVK_ENABLE_NVAPI:-1}"
export VKD3D_CONFIG="''${VKD3D_CONFIG:-dxr,dxr11}"
export WINE_FULLSCREEN_FSR="''${WINE_FULLSCREEN_FSR:-1}"

# Force ntsync (faster than fsync). CachyOS kernel ships ntsync; Proton
# autodetects but explicit makes it deterministic. No-op on kernels without
# the module — Proton falls back to fsync.
export PROTON_USE_NTSYNC="''${PROTON_USE_NTSYNC:-1}"

# Compat tools (GE-Proton, Proton CachyOS, …). Prepended so user-set value
# from environment still wins via colon-merge.
export STEAM_EXTRA_COMPAT_TOOLS_PATHS="NIXLY_COMPAT_PATHS''${STEAM_EXTRA_COMPAT_TOOLS_PATHS:+:''${STEAM_EXTRA_COMPAT_TOOLS_PATHS}}"

# Pre-launch: cover first-ever run when Steam dirs may not yet exist.
NIXLY_CONFIGURE_PROTON 2>/dev/null || true
# Post-exit: Steam rewrites config.vdf + localconfig.vdf on exit and drops
# CompatToolMapping["0"] / StartPage / notification keys it didn't set itself.
# Re-patch via EXIT trap so values persist for next launch even if Steam
# crashes or returns non-zero (set -e would otherwise skip the post-step).
trap 'NIXLY_CONFIGURE_PROTON 2>/dev/null || true' EXIT
steam NIXLY_EXTRA_STEAM_ARGS "$@"
LAUNCHER
    chmod +x $out/bin/nixly_steam

    substituteInPlace $out/bin/nixly_steam \
      --replace-fail "NIXLY_BWRAP_PATH" "${bubblewrap}/bin/bwrap" \
      --replace-fail "NIXLY_CONFIGURE_PROTON" "${configureProton}" \
      --replace-fail "NIXLY_COMPAT_PATHS" "${
        lib.makeSearchPathOutput "steamcompattool" "" extraCompatPackages
      }" \
      --replace-fail " NIXLY_EXTRA_STEAM_ARGS" "${
        lib.optionalString (extraSteamArgs != [ ])
          (" " + lib.escapeShellArgs extraSteamArgs)
      }"

    cat > $out/share/applications/nixly_steam.desktop << EOF
[Desktop Entry]
Name=Steam
Comment=Steam with Proton CachyOS and Shader Pre-Caching
Exec=$out/bin/nixly_steam %U
Icon=steam
Terminal=false
Type=Application
Categories=Network;FileTransfer;Game;
MimeType=x-scheme-handler/steam;x-scheme-handler/steamlink;
PrefersNonDefaultGPU=true
X-KDE-RunOnDiscreteGpu=true
EOF

    runHook postInstall
  '';

  postFixup = ''
    wrapProgram $out/bin/nixly_steam \
      --prefix PATH : ${lib.makeBinPath [ steam bash bubblewrap ]}
  '';

  meta = {
    description = "Steam with Proton CachyOS, Shader Pre-Caching and quiet UI auto-configured";
    longDescription = ''
      Steam wrapped for maximum gaming performance:
        - Proton CachyOS set as global default compatibility tool.
        - Shader Pre-Caching + background Vulkan shader processing on.
        - Library set as start page (global + per-user).
        - Friends + news notification popups + sounds disabled.
        - `gamemoderun %command%` injected into every game's LaunchOptions
          (empty → set; `%command%` present → replace; args-only → skip).
        - Vendor-agnostic env hints for Mesa/NVAPI/DXVK/VKD3D/Wine FSR.

      Steam rewrites localconfig.vdf on exit, so the launcher reapplies UI
      prefs on every start. Best-effort: VDF key names occasionally shift
      between Steam UI rewrites; failures log to stderr and do not block
      launch.

      GameMode not applied to Steam itself. Add `gamemoderun %command%`
      per-game in Steam launch options if desired.

      Requires programs.steam.enable = true and the proton-cachyos
      overlay (Proton CachyOS compat tool registered in Steam) in your
      NixOS configuration.
    '';
    homepage = "https://store.steampowered.com/";
    license = lib.licenses.unfreeRedistributable;
    platforms = [ "x86_64-linux" ];
    mainProgram = "nixly_steam";
  };
}
