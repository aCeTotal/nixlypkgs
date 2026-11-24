# Rebuilds this server for the panel's request.
set -Eeuo pipefail

request=$UPDATE_DIR/request.json
rev=$(jq -r .rev "$request")
target=$(jq -r .target "$request")
[[ $rev =~ ^[0-9a-f]{40}$ && $target =~ ^/nix/store/[0-9a-z]{32}-cachepanel-[^/]+$ ]] || {
  echo "refusing request: $(cat "$request")" >&2
  exit 1
}

log=$STATE_DIRECTORY/update.log
lock=$STATE_DIRECTORY/flake.lock
dump=$STATE_DIRECTORY/cachepanel.dump
: > "$log"
rm -f "$lock"

report() {
  jq -n --arg phase "$1" --arg rev "$rev" --arg target "$target" --rawfile log "$log" \
    '{phase: $phase, rev: $rev, target: $target, at: (now | todate), log: ($log | .[-4000:])}' \
    > "$UPDATE_DIR/status.json.partial"
  mv "$UPDATE_DIR/status.json.partial" "$UPDATE_DIR/status.json"
}

# The owner's flake stays the owner's.
as_owner() {
  runuser -u "$owner" -- env HOME="$owner_home" "$@"
}

fail() {
  echo "$1" >> "$log"
  if [[ -f $lock ]]; then
    cp "$lock" "$FLAKE/flake.lock"
  fi
  report failed
  exit 1
}
trap 'fail "stopped at line $LINENO"' ERR

owner=$(stat -c %U "$FLAKE")
owner_home=$(getent passwd "$owner" | cut -d: -f6)

# A newer request waits behind this one.
next() {
  [[ $(jq -r '.rev + .target' "$request") == "$rev$target" ]] || exec "$0"
}

report building
cp "$FLAKE/flake.lock" "$lock"
as_owner nix flake update "$INPUT" --flake "$FLAKE" >> "$log" 2>&1 || fail "could not update $INPUT"
locked=$(jq -r --arg input "$INPUT" '.nodes[.nodes.root.inputs[$input]].locked.rev' "$FLAKE/flake.lock")
if [[ $locked != "$rev" ]]; then
  cp "$lock" "$FLAKE/flake.lock"
  echo "main moved on to $locked" >> "$log"
  report superseded
  next
  exit 0
fi

system=$(as_owner nix build --no-link --print-out-paths "$FLAKE#nixosConfigurations.$HOST.config.system.build.toplevel" 2>> "$log") ||
  fail "the system did not build"
nix-store --add-root "$STATE_DIRECTORY/system" --realise "$system" > /dev/null
grep -qF "$target/" "$system/etc/systemd/system/nixly-cachepanel.service" || fail "the built system runs another panel"

report waiting
until [[ -n $(find "$UPDATE_DIR/idle" -newermt '-60 seconds' 2> /dev/null) ]]; do
  sleep 10
done

report switching
runuser -u postgres -- pg_dump -Fc cachepanel > "$dump"
previous=$(readlink -f /nix/var/nix/profiles/system)
nix-env -p /nix/var/nix/profiles/system --set "$system"
"$system/bin/switch-to-configuration" switch >> "$log" 2>&1 || echo "switch reported failures" >> "$log"

healthy() {
  for _ in $(seq 60); do
    if curl -sf "$HEALTH_URL" > /dev/null && systemctl show -p ExecStart nixly-cachepanel | grep -qF "$target/"; then
      return 0
    fi
    sleep 2
  done
  return 1
}

if healthy; then
  report "done"
  next
  exit 0
fi

echo "the new panel is not healthy; rolling back" >> "$log"
nix-env -p /nix/var/nix/profiles/system --set "$previous"
"$previous/bin/switch-to-configuration" switch >> "$log" 2>&1 || echo "rollback switch reported failures" >> "$log"
systemctl stop nixly-cachepanel
runuser -u postgres -- pg_restore --clean --if-exists -d cachepanel "$dump" >> "$log" 2>&1
systemctl start nixly-cachepanel
fail "rolled back to $previous"
