#!/usr/bin/env bash
set -euo pipefail

export WINEPREFIX="${GAEA_WINEPREFIX:-${XDG_DATA_HOME:-$HOME/.local/share}/gaea/prefix}"
export WINEARCH=win64
export WINEFSYNC=1
export WINEDEBUG="${WINEDEBUG:--all}"

export DOTNET_ROOT='C:\dotnet'
export DOTNET_CLI_TELEMETRY_OPTOUT=1
export DOTNET_NOLOGO=1

export WINEDLLOVERRIDES="d3d9,d3d10core,d3d11,d3d12,d3d12core,dxgi=n;winemenubuilder.exe=;${WINEDLLOVERRIDES:-}"
export DXVK_CONFIG="dxgi.hideNvidiaGpu = False;${DXVK_CONFIG:-}"
export LD_LIBRARY_PATH="@driverLink@/lib:${LD_LIBRARY_PATH:-}"

if [ "${GAEA_WAYLAND:-0}" = 1 ]; then
  unset DISPLAY
fi

stamp="$WINEPREFIX/.gaea-version"
if [ "$(cat "$stamp" 2>/dev/null || true)" != "@out@" ]; then
  mkdir -p "$WINEPREFIX"
  wineboot --init
  wineserver -w

  wine reg add 'HKCU\Software\Microsoft\Avalon.Graphics' \
    /v DisableHWAcceleration /t REG_DWORD /d 1 /f
  wineserver -w

  install -m644 \
    @dxvk@/x64/d3d9.dll \
    @dxvk@/x64/d3d10core.dll \
    @dxvk@/x64/d3d11.dll \
    @dxvk@/x64/dxgi.dll \
    @out@/share/gaea/vkd3d/d3d12.dll \
    @out@/share/gaea/vkd3d/d3d12core.dll \
    @out@/share/gaea/nvlibs/nvcuda.dll \
    "$WINEPREFIX/drive_c/windows/system32/"

  ln -sfn @out@/share/gaea/dotnet "$WINEPREFIX/drive_c/dotnet"

  keep="$WINEPREFIX/.gaea-data"
  rm -rf "$keep"
  if [ -d "$WINEPREFIX/drive_c/Gaea/Data" ]; then
    mv "$WINEPREFIX/drive_c/Gaea/Data" "$keep"
  fi

  rm -rf "$WINEPREFIX/drive_c/Gaea"
  cp -r @out@/share/gaea/app "$WINEPREFIX/drive_c/Gaea"
  chmod -R u+w "$WINEPREFIX/drive_c/Gaea"

  if [ -d "$keep" ]; then
    rm -rf "$WINEPREFIX/drive_c/Gaea/Data"
    mv "$keep" "$WINEPREFIX/drive_c/Gaea/Data"
  fi

  echo "@out@" > "$stamp"
fi

cd "$WINEPREFIX/drive_c/Gaea"

wine ./Gaea.exe "$@" &

wine @out@/share/gaea/embed/gaea-embed.exe >/dev/null 2>&1 &
embed_pid=$!
trap 'kill "$embed_pid" 2>/dev/null || true' EXIT

wait "$embed_pid"
