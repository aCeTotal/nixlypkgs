#!/usr/bin/env bash
# Stand-in for the `code` binary, on PATH only for the engine's own processes.
#
# Unreal's Visual Studio Code source-code accessor is the one Linux accessor
# that resolves its editor at runtime - VisualStudioCodeSourceCodeAccessor.cpp
# runs `bash -c "type -p code"`. With nothing to find it marks itself invalid,
# which is the "Your IDE Visual Studio Code is missing or incorrectly
# configured" banner in the project dialog, and "Open in IDE" silently does
# nothing. This translates the accessor's argv into Totalvim instead.
#
# The accessor calls us as:  code <solution> [-g <file>:<line>:<col>] [<file>...]
set -euo pipefail

files=()
line=""
goto=0
for arg in "$@"; do
  if [ "$arg" = "-g" ]; then
    goto=1
    continue
  fi
  case "$arg" in
    -*) continue ;;
    # The solution argument is the generated workspace or the project dir;
    # Totalvim has no use for either.
    *.code-workspace | *.uproject) continue ;;
  esac
  if [ "$goto" = 1 ]; then
    goto=0
    line="${arg#*:}"
    line="${line%%:*}"
    files+=("${arg%%:*}")
  elif [ -f "$arg" ]; then
    files+=("$arg")
  fi
done

[ "${#files[@]}" -gt 0 ] || exit 0

nvim="$(command -v nvim || true)"
if [ -z "$nvim" ]; then
  echo "code shim: nvim (Totalvim) not found on PATH" >&2
  exit 1
fi

# The engine has no terminal of its own to hand a TUI editor, so pick one.
term="${TERMINAL:-}"
if [ -z "$term" ]; then
  for candidate in alacritty foot kitty wezterm; do
    if command -v "$candidate" >/dev/null; then
      term="$candidate"
      break
    fi
  done
fi
if [ -z "$term" ]; then
  echo "code shim: no terminal found to run Totalvim in" >&2
  exit 1
fi

exec "$term" -e "$nvim" ${line:+"+$line"} "${files[@]}"
