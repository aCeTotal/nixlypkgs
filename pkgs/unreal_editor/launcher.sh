#!/usr/bin/env bash
set -euo pipefail

engine="@engine@"

if [ "$(ulimit -Sn)" -lt 65536 ]; then
  ulimit -Sn "$(ulimit -Hn)" 2>/dev/null || true
fi

driver="${UE5_VIDEODRIVER:-x11}"
if [ "$driver" = x11 ] && [ -z "${DISPLAY:-}" ]; then
  driver=wayland
fi
export SDL_VIDEO_DRIVER="$driver"
export SDL_VIDEODRIVER="$driver"
if [ "$driver" = wayland ]; then
  export SDL_VIDEO_WAYLAND_PREFER_LIBDECOR=1
  export LIBDECOR_PLUGIN_DIR="@libdecorplugins@"
fi

export LD_LIBRARY_PATH="@libs@${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export PATH="@ide@:@path@:$PATH"

cache="${XDG_CACHE_HOME:-$HOME/.cache}"
ddc="$cache/UnrealEngine/DerivedDataCache"
export MESA_SHADER_CACHE_DIR="$cache/mesa_shader_cache"
export MESA_SHADER_CACHE_MAX_SIZE=12G
mkdir -p "$ddc" "$MESA_SHADER_CACHE_DIR"

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

export DOTNET_ROOT="$root/Engine/Binaries/ThirdParty/DotNet/10.0/linux-x64"
export DOTNET_CLI_TELEMETRY_OPTOUT=1
export DOTNET_NOLOGO=1
export DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1

exec env "UE-LocalDataCachePath=$ddc" @bwrap@ \
  --dev-bind / / \
  --overlay-src "$engine" --overlay "$rw" "$work" "$root" \
  -- "$root/@exe@" "$@"
