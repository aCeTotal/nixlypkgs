#!/usr/bin/env bash
# Launcher for the Unreal Engine binaries under @engine@.
# Placeholders (@engine@, @exe@, @libs@, @path@, @libdecorplugins@, @bwrap@)
# are filled in at build time.
set -euo pipefail

engine="@engine@"

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
export PATH="@ide@:@path@:$PATH"

# --- Caches -----------------------------------------------------------------
# The engine tree is read-only in the Nix store, so every cache has to live in
# $HOME. Persisting them is what turns the second editor start from ~15 min of
# shader compilation into seconds.
cache="${XDG_CACHE_HOME:-$HOME/.cache}"
ddc="$cache/UnrealEngine/DerivedDataCache"
export MESA_SHADER_CACHE_DIR="$cache/mesa_shader_cache"
export MESA_SHADER_CACHE_MAX_SIZE=12G
mkdir -p "$ddc" "$MESA_SHADER_CACHE_DIR"

# --- Engine mount point -----------------------------------------------------
# Two store properties break the engine, and one overlay mount fixes both.
#
# Path length: every failed file lookup goes through UE's case-insensitivity
# workaround (FUnixFileMapper), which readdir()s each parent directory of the
# requested path from / downwards. With the engine living in the store that is
# a full scan of /nix/store - tens of thousands of entries - per miss, and a
# miss is only remembered for 500 ms, so config probing at startup never
# finishes. The engine root comes from /proc/self/exe, so mounting it on a
# short path is enough for the mapper to only ever walk small directories.
#
# Writability: UnrealBuildTool writes inside the engine tree even though this
# is an installed build - Engine/Intermediate/TargetInfo.json, ProjectFiles/,
# and a .ubtplugin.csproj.props next to every UBT plugin under Engine/Plugins.
# Store trees are 0555, so those fail with "Read-only file system" and the
# editor reports "Unable to read target info for engine" and refuses to
# generate project files. An overlay puts the writes in $HOME.
#
# overlayfs takes a directory's mode from the upper layer when the directory
# exists there, so the upper is pre-seeded with the engine's directory tree
# (65k empty dirs, ~1 s, no file copies). Without that seeding the merged
# directories keep the store's 0555 and creating a file still fails.
root="$cache/UnrealEngine/engine"
rw="$cache/UnrealEngine/rw"
work="$cache/UnrealEngine/work"
stamp="$cache/UnrealEngine/rw.engine-path"
if [ "$(cat "$stamp" 2>/dev/null)" != "$engine" ]; then
  echo "seeding writable engine overlay from $engine" >&2
  rm -rf "$rw" "$work" "$stamp"
  mkdir -p "$rw"
  ( cd "$engine" && find . -mindepth 1 -type d -printf '%P\0' ) \
    | ( cd "$rw" && xargs -0 -r mkdir -p )
  printf '%s' "$engine" > "$stamp"
fi
mkdir -p "$root" "$work"

# UnrealBuildTool / AutomationTool run on the engine's bundled .NET.
export DOTNET_ROOT="$root/Engine/Binaries/ThirdParty/DotNet/10.0/linux-x64"
export DOTNET_CLI_TELEMETRY_OPTOUT=1
export DOTNET_NOLOGO=1
export DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1

# UE reads the local DDC location from an env var whose name contains a dash,
# so it cannot be exported from bash - hand it over through env(1).
exec env "UE-LocalDataCachePath=$ddc" @bwrap@ \
  --dev-bind / / \
  --overlay-src "$engine" --overlay "$rw" "$work" "$root" \
  -- "$root/@exe@" "$@"
