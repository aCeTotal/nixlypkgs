{
  lib,
  stdenvNoCC,
  makeWrapper,
  writeScript,
  steam,
  python3,
  bash,
}:

let
  configureProton = writeScript "nixly-steam-configure-proton" ''
    #!${python3}/bin/python3
    """Auto-configure Proton Experimental (Bleeding Edge) for Steam."""
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

        # Global default: Proton Experimental
        compat = ensure(steam_cfg, ["CompatToolMapping"])
        if "0" not in compat or not isinstance(compat.get("0"), dict):
            compat["0"] = {}
        entry = compat["0"]
        if entry.get("name") != "proton_experimental":
            entry["name"] = "proton_experimental"
            entry["config"] = ""
            entry["priority"] = "250"
            changed = True

        # Proton Experimental (appid 1493710) -> bleeding_edge beta
        apps = ensure(steam_cfg, ["Apps"])
        if "1493710" not in apps or not isinstance(apps.get("1493710"), dict):
            apps["1493710"] = {}
        if apps["1493710"].get("BetaKey") != "bleeding_edge":
            apps["1493710"]["BetaKey"] = "bleeding_edge"
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
            print("[nixly_steam] Proton Experimental (Bleeding Edge) + Shader Pre-Caching configured.", file=sys.stderr)

    if __name__ == "__main__":
        main()
  '';

in

stdenvNoCC.mkDerivation {
  pname = "nixly_steam";
  version = "1.0.0.85";

  dontUnpack = true;
  dontBuild = true;

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin $out/share/applications

    cat > $out/bin/nixly_steam <<'LAUNCHER'
#!/usr/bin/env bash
set -euo pipefail
NIXLY_CONFIGURE_PROTON 2>/dev/null || true
exec steam "$@"
LAUNCHER
    chmod +x $out/bin/nixly_steam

    substituteInPlace $out/bin/nixly_steam \
      --replace-fail "NIXLY_CONFIGURE_PROTON" "${configureProton}"

    cat > $out/share/applications/nixly_steam.desktop << EOF
[Desktop Entry]
Name=Steam
Comment=Steam with Proton Experimental (Bleeding Edge) and Shader Pre-Caching
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
      --prefix PATH : ${lib.makeBinPath [ steam bash ]}
  '';

  meta = {
    description = "Steam with Proton Experimental (Bleeding Edge) and Shader Pre-Caching auto-configured";
    longDescription = ''
      Steam wrapped with automatic Proton Experimental (Bleeding Edge)
      configuration. On each launch, the wrapper ensures that Proton
      Experimental is set as the global default compatibility tool,
      the Bleeding Edge beta branch is selected, Shader Pre-Caching
      is enabled, and background processing of Vulkan shaders is on.

      Requires programs.steam.enable = true in your NixOS configuration.
    '';
    homepage = "https://store.steampowered.com/";
    license = lib.licenses.unfreeRedistributable;
    platforms = [ "x86_64-linux" ];
    mainProgram = "nixly_steam";
  };
}
