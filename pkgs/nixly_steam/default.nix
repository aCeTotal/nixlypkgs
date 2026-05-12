{
  lib,
  stdenvNoCC,
  makeWrapper,
  writeScript,
  steam,
  python3,
  bash,
  bubblewrap,
  gamescope,
  wlr-randr,
  gamemode,
  proton-ge-bin,
  proton-cachyos,
  writeShellScript,
  # GPU vendor to bake universally-safe env defaults for. "auto" detects at
  # launch via /sys/class/drm/cardN/device/vendor + /proc/driver/nvidia/version
  # and sets the matching vendor block. "amd"/"nvidia"/"intel" bakes the
  # selected vendor's block directly (skips runtime detection). The "generic"
  # block (vendor-agnostic Proton/Wine flags) always applies.
  gpuVendor ? "auto",
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
  validVendors = [ "auto" "amd" "nvidia" "intel" ];

  gpuParams = assert
    (lib.elem gpuVendor validVendors)
    || throw "nixly_steam: gpuVendor must be one of ${
      lib.concatStringsSep ", " validVendors
    } (got ${gpuVendor})";
    import ./gpu-params.nix;

  # Render `attrset { K = V; }` as bash `export K="''${K:-V}"` lines so user-set
  # env always wins over the bake-in defaults.
  exportLines = attrs:
    lib.concatStringsSep "\n" (lib.mapAttrsToList
      (k: v: ''export ${k}="''${${k}:-${v}}"'')
      attrs);

  amdBlock = exportLines gpuParams.amd;
  nvidiaBlock = exportLines gpuParams.nvidia;
  intelBlock = exportLines gpuParams.intel;
  genericBlock = exportLines gpuParams.generic;

  # Vendor-specific env block. "auto" → bash runtime-detect; explicit vendor →
  # bake that vendor's block directly. "generic" block (Proton/Wine flags
  # applicable everywhere) always trails.
  gpuEnvScript = writeShellScript "nixly-steam-gpu-env" (
    if gpuVendor == "auto" then ''
      # Detect GPU vendor of dGPU (NVIDIA wins; else AMD > Intel by /sys IDs).
      nixly_vendor=unknown
      if [ -e /proc/driver/nvidia/version ]; then
        nixly_vendor=nvidia
      else
        for nixly_d in /sys/class/drm/card[0-9]*; do
          [ -f "$nixly_d/device/vendor" ] || continue
          case "$(cat "$nixly_d/device/vendor" 2>/dev/null)" in
            0x1002) nixly_vendor=amd; break ;;
            0x8086) [ "$nixly_vendor" = unknown ] && nixly_vendor=intel ;;
          esac
        done
        unset nixly_d
      fi
      case "$nixly_vendor" in
        amd)
      ${amdBlock}
          ;;
        nvidia)
      ${nvidiaBlock}
          ;;
        intel)
      ${intelBlock}
          ;;
      esac
      unset nixly_vendor
      ${genericBlock}
    '' else ''
      # gpuVendor=${gpuVendor} baked at build time.
      ${exportLines gpuParams.${gpuVendor}}
      ${genericBlock}
    ''
  );

  # Per-game wrapper: detect focused nixlytile output via niri-IPC, query
  # its max mode via wlr-randr, exec gamescope fullscreen on that output
  # with gamemoderun chaining the actual game. Fallback to first enabled
  # output if IPC unavailable. Steam stores LaunchOptions as text, so the
  # absolute store path is baked into every per-app LaunchOptions string;
  # `configureProton` re-patches on launch so a new build's path replaces
  # the old one before games run.
  gamescopeWrap = writeScript "nixly-gamescope-wrap" ''
    #!${python3}/bin/python3
    """Wrap %command% with gamescope at focused output's max resolution."""
    import json, os, socket, subprocess, sys, time

    NIRI_SOCK = os.environ.get("NIRI_SOCKET", "")
    WLR_RANDR = "${wlr-randr}/bin/wlr-randr"
    GAMESCOPE = "${gamescope}/bin/gamescope"
    GAMEMODERUN = "${gamemode}/bin/gamemoderun"

    def focused_output():
        if not NIRI_SOCK or not os.path.exists(NIRI_SOCK):
            return None
        try:
            s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            s.settimeout(0.5)
            s.connect(NIRI_SOCK)
            s.sendall(b'"EventStream"\n')
            buf = b""
            deadline = time.time() + 1.5
            while time.time() < deadline:
                try:
                    s.settimeout(max(0.05, deadline - time.time()))
                    chunk = s.recv(65536)
                except socket.timeout:
                    break
                if not chunk:
                    break
                buf += chunk
                if b"WorkspacesChanged" in buf and buf.endswith(b"\n"):
                    break
            try:
                s.close()
            except Exception:
                pass
            for line in buf.split(b"\n"):
                line = line.strip()
                if not line:
                    continue
                try:
                    msg = json.loads(line)
                except Exception:
                    continue
                if not isinstance(msg, dict):
                    continue
                wsc = msg.get("WorkspacesChanged")
                if not isinstance(wsc, dict):
                    continue
                for w in wsc.get("workspaces", []) or []:
                    if isinstance(w, dict) and w.get("is_focused"):
                        return w.get("output")
        except Exception:
            return None
        return None

    def pick_mode(target_name):
        try:
            raw = subprocess.check_output([WLR_RANDR, "--json"], timeout=2.0)
            outputs = json.loads(raw)
        except Exception:
            return None
        if not isinstance(outputs, list):
            return None
        chosen = None
        if target_name:
            for o in outputs:
                if isinstance(o, dict) and o.get("name") == target_name:
                    chosen = o
                    break
        if chosen is None:
            for o in outputs:
                if isinstance(o, dict) and o.get("enabled"):
                    chosen = o
                    break
        if chosen is None:
            return None
        modes = chosen.get("modes") or []
        if not modes:
            return None
        def key(m):
            return (
                int(m.get("width") or 0) * int(m.get("height") or 0),
                float(m.get("refresh") or 0),
            )
        best = max(modes, key=key)
        try:
            return (
                str(chosen.get("name") or ""),
                int(best["width"]),
                int(best["height"]),
                int(round(float(best.get("refresh") or 60))),
            )
        except Exception:
            return None

    def main():
        name = focused_output()
        mode = pick_mode(name)
        cmd = [GAMESCOPE, "-f", "--backend", "wayland"]
        if mode:
            n, w, h, hz = mode
            cmd += ["-W", str(w), "-H", str(h)]
            if hz > 0:
                cmd += ["-r", str(hz)]
            if n:
                cmd += ["--prefer-output", n]
        cmd += ["--", GAMEMODERUN, *sys.argv[1:]]
        os.execvp(cmd[0], cmd)

    if __name__ == "__main__":
        main()
  '';

  configureProton = writeScript "nixly-steam-configure-proton" ''
    #!${python3}/bin/python3
    """Auto-configure Steam: Proton CachyOS default, shader pre-cache,
    Library as start page, friends + news popups off, gamescope wrapper
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
        # Inject `<wrap> %command%` into per-app LaunchOptions so every game
        # runs under gamescope (fullscreen at focused output's max mode) and
        # gamemoderun (CPU governor + IO prio). The wrap binary chains
        # gamemoderun internally. Re-runs on each Steam start so newly
        # installed games get covered, and so a rebuild's new store path
        # replaces the prior one in already-patched entries.
        wrap = "${gamescopeWrap}"
        wrap_marker = "nixly-gamescope-wrap"
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

        import re as _re
        # writeScript creates /nix/store/<hash>-nixly-gamescope-wrap as the
        # file path itself (no /bin/ suffix).
        wrap_path_re = _re.compile(
            r"/nix/store/[A-Za-z0-9]+-nixly-gamescope-wrap"
        )

        for appid, app in apps.items():
            if not isinstance(app, dict):
                continue
            opts = app.get("LaunchOptions", "")

            # Already wrapped — rewrite the store path if it has drifted to
            # an older build, otherwise leave alone.
            if wrap_marker in opts:
                new_opts = wrap_path_re.sub(wrap, opts)
                if new_opts != opts:
                    app["LaunchOptions"] = new_opts
                    changed = True
                continue

            if not opts:
                app["LaunchOptions"] = new_prefix
                changed = True
                continue

            # Migrate prior `gamemoderun %command%` injection — wrap handles
            # gamemode internally now.
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
                # Args-only launch options: prepending would make Steam launch
                # the wrap as the game binary's args. Skip to avoid breakage.
                print(
                    f"[nixly_steam] app {appid}: args-only LaunchOptions "
                    f"({opts!r}); skipping gamescope wrap.",
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

        # Per-game gamescope+gamemode auto-apply
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

# GPU-vendor-specific env (gpuVendor build-time arg: auto/amd/nvidia/intel)
# plus generic Proton/Wine flags. Each var uses `${VAR:-default}` so a
# user-set value from the parent env always wins. See gpu-params.nix.
source NIXLY_GPU_ENV

# Force discrete GPU on hybrid (PRIME) systems. Detection-gated so vars
# only apply when a second GPU exists — single-GPU NVIDIA/AMD/Intel skip
# entirely (avoids __GLX_VENDOR_LIBRARY_NAME=nvidia breaking GL on
# AMD-only, and DRI_PRIME=1 confusing mesa on single-GPU).
nixly_gpu_count=$(ls -d /sys/class/drm/renderD* 2>/dev/null | wc -l)
if [ "$nixly_gpu_count" -gt 1 ]; then
  if [ -e /proc/driver/nvidia/version ]; then
    # NVIDIA hybrid (Intel/AMD iGPU + NVIDIA dGPU). Offload mode: GL via
    # nvidia GLX vendor, Vulkan only sees NVIDIA device.
    export __NV_PRIME_RENDER_OFFLOAD="''${__NV_PRIME_RENDER_OFFLOAD:-1}"
    export __NV_PRIME_RENDER_OFFLOAD_PROVIDER="''${__NV_PRIME_RENDER_OFFLOAD_PROVIDER:-NVIDIA-G0}"
    export __GLX_VENDOR_LIBRARY_NAME="''${__GLX_VENDOR_LIBRARY_NAME:-nvidia}"
    export __VK_LAYER_NV_optimus="''${__VK_LAYER_NV_optimus:-NVIDIA_only}"
  else
    # Mesa-only hybrid (Intel iGPU + AMD dGPU). DRI_PRIME=1 picks the
    # non-default (discrete) provider for GL; mesa's vk_device_select
    # layer also honors DRI_PRIME for Vulkan device selection.
    export DRI_PRIME="''${DRI_PRIME:-1}"
  fi
fi
unset nixly_gpu_count

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
      --replace-fail "NIXLY_GPU_ENV" "${gpuEnvScript}" \
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
        - `nixly-gamescope-wrap %command%` injected into every game's
          LaunchOptions: gamescope fullscreen on the nixlytile-focused
          output at its max mode, chaining gamemoderun for the actual
          game process (empty → set; `gamemoderun %command%` → migrated;
          `%command%` present → replace; args-only → skip).
        - GPU-vendor-specific env defaults (gpuVendor arg, default "auto"):
          AMD → RADV_PERFTEST/AMD_VULKAN_ICD/mesa_glthread/shader-cache.
          NVIDIA → __GL_THREADED_OPTIMIZATIONS/__GL_GSYNC_ALLOWED/
          __GL_VRR_ALLOWED/__GL_SHADER_DISK_CACHE_SIZE/NVAPI.
          Intel → ANV_ENABLE_PIPELINE_CACHE/mesa_glthread/shader-cache.
          Generic block (VKD3D_CONFIG=dxr,dxr11/WINE_FULLSCREEN_FSR/
          PROTON_USE_NTSYNC) always applies. See gpu-params.nix.

      Steam rewrites localconfig.vdf on exit, so the launcher reapplies UI
      prefs on every start. Best-effort: VDF key names occasionally shift
      between Steam UI rewrites; failures log to stderr and do not block
      launch.

      The wrap script reads `NIRI_SOCKET` (exported by nixlytile) to find
      the focused output, then `wlr-randr --json` for that output's max
      mode (W×H by area, refresh as tiebreaker). Falls back to first
      enabled output if IPC unavailable. GameMode is not applied to Steam
      itself — only to the game process inside gamescope.

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
