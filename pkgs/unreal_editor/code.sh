#!/usr/bin/env bash
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
