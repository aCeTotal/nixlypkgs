#!/usr/bin/env bash
# Delete quarantined malware, keep what merely could not be scanned.
set -uo pipefail

events=/run/nixly-dlgate/events
declare -A sig

event() {
  printf '%s|%s|%s|%s\n' "$1" "$2" "$3" "${4:-}" >>"$events"
}

journalctl -f -n0 -o cat -u clamav-clamonacc | while IFS= read -r line; do
  case $line in
    *" FOUND")
      src=${line%%: *}
      s=${line##*: }
      sig[$src]=${s% FOUND}
      ;;
    *": moved to '"*)
      src=${line%%: moved to *}
      src=${src%% (real path:*}
      dst=${line##*moved to \'}
      dst=${dst%\'*}
      s=${sig[$src]:-}
      unset 'sig[$src]'
      # Deleting is the only irreversible outcome, so it needs a known verdict.
      case $s in
        ""|*ncrypted*|*Limits.Exceeded*)
          event held "$(basename "$src")" "${s:-unscannable}" "$(basename "$dst")" ;;
        *)
          rm -f -- "$dst"
          event threat "$(basename "$src")" "$s" ;;
      esac
      ;;
  esac
done
