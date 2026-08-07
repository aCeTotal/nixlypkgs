#!/usr/bin/env bash
# Launcher for the Unreal Engine binaries under @engine@.
# Placeholders (@engine@, @exe@, @libs@, @path@, @libdecorplugins@) are filled
# in at build time.
set -euo pipefail

engine="@engine@"
exe="$engine/@exe@"

# --- File descriptors -------------------------------------------------------
# The editor keeps thousands of .uasset/shader files open; the usual 1024 soft
# limit shows up as random "failed to open" asset errors. Raise to the hard cap.
if [ "$(ulimit -Sn)" -lt 65536 ]; then
  ulimit -Sn "$(ulimit -Hn)" 2>/dev/null || true
fi

# --- Video backend ----------------------------------------------------------
# UE 5.8 ships SDL3, whose Wayland backend is the native path (no XWayland
# blur, correct fractional scaling). Override with UE5_VIDEODRIVER=x11 if
# torn-off editor tabs or tooltips end up mispositioned - Wayland has no
# absolute window placement, which Slate occasionally wants.
driver="${UE5_VIDEODRIVER:-wayland}"
if [ "$driver" = wayland ] && [ -z "${WAYLAND_DISPLAY:-}" ]; then
  driver=x11
fi
export SDL_VIDEO_DRIVER="$driver"
export SDL_VIDEODRIVER="$driver"
if [ "$driver" = wayland ]; then
  # Server-side decorations are not guaranteed on wlroots compositors, so let
  # SDL draw them via libdecor - which only finds its plugins if pointed at
  # them explicitly on NixOS.
  export SDL_VIDEO_WAYLAND_PREFER_LIBDECOR=1
  export LIBDECOR_PLUGIN_DIR="@libdecorplugins@"
fi

# --- Runtime paths ----------------------------------------------------------
export LD_LIBRARY_PATH="@libs@${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export PATH="@path@:$PATH"

# UnrealBuildTool / AutomationTool run on the engine's bundled .NET.
export DOTNET_ROOT="$engine/Engine/Binaries/ThirdParty/DotNet/10.0/linux-x64"
export DOTNET_CLI_TELEMETRY_OPTOUT=1
export DOTNET_NOLOGO=1
export DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1

# --- Caches -----------------------------------------------------------------
# The engine tree is read-only in the Nix store, so every cache has to live in
# $HOME. Persisting them is what turns the second editor start from ~15 min of
# shader compilation into seconds.
cache="${XDG_CACHE_HOME:-$HOME/.cache}"
ddc="$cache/UnrealEngine/DerivedDataCache"
export MESA_SHADER_CACHE_DIR="$cache/mesa_shader_cache"
export MESA_SHADER_CACHE_MAX_SIZE=12G
mkdir -p "$ddc" "$MESA_SHADER_CACHE_DIR"

# UE reads the local DDC location from an env var whose name contains a dash,
# so it cannot be exported from bash - hand it over through env(1).
exec env "UE-LocalDataCachePath=$ddc" "$exe" "$@"
