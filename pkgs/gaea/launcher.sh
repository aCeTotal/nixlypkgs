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

# DXVK maskerer NVIDIA-kort som AMD by default (dxgi.hideNvidiaGpu). Gaea
# leverer bade CUDA (cudart64_12.dll) og HIP (Gaea.AdaptiveCpp.HIP.dll) og
# velger compute-backend etter vendor-ID — pa NVIDIA rapporterte viewporten
# "Vendor: ATI / 0x73df". Av med maskeringen: NVIDIA, AMD og Intel melder da
# sin egen vendor, og alle tre far samme oppforsel.
export DXVK_CONFIG="dxgi.hideNvidiaGpu = False;${DXVK_CONFIG:-}"

# Gaea sin GPU-compute er AdaptiveCpp/SYCL. CUDA-backenden (hipSYCL/
# rt-backend-cuda.dll + cudart64_12.dll) importerer nvcuda.dll, som Wine
# ikke leverer — uten den feiler backenden med "Library nvcuda.dll not
# found" og bare OMP (CPU) star igjen. nvidia-libs sin nvcuda er en winelib
# som dlopen'er libcuda.so.1, saa driver-libmappa maa ligge i LD_LIBRARY_PATH.
export LD_LIBRARY_PATH="@driverLink@/lib:${LD_LIBRARY_PATH:-}"

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

  # Gaea-UI er WPF og rendrer via D3D9Ex. DXVK sin D3D9-swapchain blir hvit
  # ved resize/fullskjerm (tiling-WM tvinger begge). Software-rendering av WPF
  # fjerner den pathen helt — 3D-viewporten (Unity/D3D11) er upaavirket.
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

  # Gaea skriver logger, cache og lisensfil i sin egen mappe, saa den maa vaere skrivbar.
  rm -rf "$WINEPREFIX/drive_c/Gaea"
  cp -r @out@/share/gaea/app "$WINEPREFIX/drive_c/Gaea"
  chmod -R u+w "$WINEPREFIX/drive_c/Gaea"

  echo "@out@" > "$stamp"
fi

cd "$WINEPREFIX/drive_c/Gaea"

# Gaea kjoerer 3D-viewporten i en egen prosess (Gaea.Viewport.exe, Unity) og
# embedder vinduet i hovedvinduet med SetParent. Den reparentingen skjer ikke
# under Wine: uten virtual desktop blir viewporten et eget toplevel som
# tiling-WM-en legger i sin egen tile, den committer 1x1 og panelet i UI-et
# forblir svart. Inne i en Wine-desktop havner vinduet der Gaea plasserer det,
# og gaea-embed.exe fjerner Wine-rammen rundt det. Desktopen foelger
# vindustoerrelsen WM-en gir den, saa startstoerrelsen er bare et utgangspunkt.
desktop="Gaea,${GAEA_DESKTOP_SIZE:-1920x1080}"

wine explorer "/desktop=$desktop" ./Gaea.exe "$@" &
gaea_pid=$!

# Kobler seg til desktopen som allerede finnes; avslutter selv naar Gaea er ute.
(
  sleep 5
  wine explorer "/desktop=$desktop" @out@/share/gaea/embed/gaea-embed.exe
) >/dev/null 2>&1 &

wait "$gaea_pid"
