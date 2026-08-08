#!/usr/bin/env bash
# Starter QuadSpinner Gaea i en dedikert Wine-prefix.
set -euo pipefail

export WINEPREFIX="${GAEA_WINEPREFIX:-${XDG_DATA_HOME:-$HOME/.local/share}/gaea/prefix}"
export WINEARCH=win64
export WINEFSYNC=1
export WINEDEBUG="${WINEDEBUG:--all}"

# Gaea er en framework-avhengig .NET 8-app. apphost-en finner runtime via DOTNET_ROOT.
export DOTNET_ROOT='C:\dotnet'
export DOTNET_CLI_TELEMETRY_OPTOUT=1
export DOTNET_NOLOGO=1

# DXVK erstatter wined3d: Gaea.Viewport er en Unity-player som krever D3D11,
# og WPF-UI-en renderer via D3D9Ex. vkd3d-proton dekker D3D12 — Gaea skipper
# med D3D12 Agility SDK og kan velge den pathen.
export WINEDLLOVERRIDES="d3d9,d3d10core,d3d11,d3d12,d3d12core,dxgi=n;winemenubuilder.exe=;${WINEDLLOVERRIDES:-}"

# Standard: X11-driveren mot Xwayland (best testet, DXVK/Vulkan gaar rett gjennom).
# GAEA_WAYLAND=1 skjuler DISPLAY slik at Wine faller tilbake til winewayland.
if [ "${GAEA_WAYLAND:-0}" = 1 ]; then
  unset DISPLAY
fi

stamp="$WINEPREFIX/.gaea-version"
if [ "$(cat "$stamp" 2>/dev/null || true)" != "@out@" ]; then
  mkdir -p "$WINEPREFIX"
  wineboot --init
  wineserver -w

  install -m644 \
    @dxvk@/x64/d3d9.dll \
    @dxvk@/x64/d3d10core.dll \
    @dxvk@/x64/d3d11.dll \
    @dxvk@/x64/dxgi.dll \
    @out@/share/gaea/vkd3d/d3d12.dll \
    @out@/share/gaea/vkd3d/d3d12core.dll \
    "$WINEPREFIX/drive_c/windows/system32/"

  ln -sfn @out@/share/gaea/dotnet "$WINEPREFIX/drive_c/dotnet"

  # Gaea skriver logger, cache og lisensfil i sin egen mappe, saa den maa vaere skrivbar.
  rm -rf "$WINEPREFIX/drive_c/Gaea"
  cp -r @out@/share/gaea/app "$WINEPREFIX/drive_c/Gaea"
  chmod -R u+w "$WINEPREFIX/drive_c/Gaea"

  echo "@out@" > "$stamp"
fi

cd "$WINEPREFIX/drive_c/Gaea"
exec wine ./Gaea.exe "$@"
