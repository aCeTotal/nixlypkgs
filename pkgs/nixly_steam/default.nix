{
  lib,
  stdenvNoCC,
  makeWrapper,
  writeScript,
  steam,
  python3,
  bash,
  bubblewrap,
  # Extra CLI args appended to the steam invocation. Default disables CEF GPU
  # compositing — required under Niri/xwayland-satellite where rootless
  # XWayland breaks CEF compositing → Steam UI black window.
  extraSteamArgs ? [ "-cef-disable-gpu-compositing" ],
}:

let
  configureProton = writeScript "nixly-steam-configure-proton" ''
    #!${python3}/bin/python3
    """Auto-configure Proton CachyOS as default Proton for Steam."""
    import os, re, sys, shutil

    def find_config():
        xdg = os.environ.get("XDG_DATA_HOME", os.path.expanduser("~/.local/share"))
        for p in [
            os.path.join(xdg, "Steam", "config", "config.vdf"),
            os.path.expanduser("~/.steam/steam/config/config.vdf"),
            os.path.expanduser("~/.steam/root/config/config.vdf"),
        ]:
            if os.path.isfile(p):
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

    def main():
        path = find_config()
        if path is None:
            print(
                "[nixly_steam] Steam config not found. "
                "Settings will be configured after first Steam launch.",
                file=sys.stderr,
            )
            return

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
        if shader.get("EnableShaderBackgroundProcessing") != "1":
            shader["EnableShaderBackgroundProcessing"] = "1"
            changed = True

        if changed:
            backup = path + ".nixly_backup"
            if not os.path.exists(backup):
                shutil.copy2(path, backup)
            with open(path, "w") as f:
                f.write(dump(data))
                f.write("\n")
            print("[nixly_steam] Proton CachyOS + Shader Pre-Caching configured.", file=sys.stderr)

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

NIXLY_CONFIGURE_PROTON 2>/dev/null || true
exec steam NIXLY_EXTRA_STEAM_ARGS "$@"
LAUNCHER
    chmod +x $out/bin/nixly_steam

    substituteInPlace $out/bin/nixly_steam \
      --replace-fail "NIXLY_BWRAP_PATH" "${bubblewrap}/bin/bwrap" \
      --replace-fail "NIXLY_CONFIGURE_PROTON" "${configureProton}" \
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
    description = "Steam with Proton CachyOS and Shader Pre-Caching auto-configured";
    longDescription = ''
      Steam wrapped for maximum gaming performance:
        - Proton CachyOS set as global default compatibility tool.
        - Shader Pre-Caching + background Vulkan shader processing on.
        - Vendor-agnostic env hints for Mesa/NVAPI/DXVK/VKD3D/Wine FSR.

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
