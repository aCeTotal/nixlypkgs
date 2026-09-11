# Nightly unattended update at 06:00: build the next generation as the
# user (via the existing nixlyos-stage machinery, which the 5-minute timer
# has usually finished long before), adopt it as the system profile and
# reboot into it. Runs as root, so no password is ever asked for. Nothing
# happens — and no reboot — when there is nothing new.
{ pkgs, lib, config, nixlyUser, ... }:

lib.mkIf (config.nixlyos.mode == "htpc") {

  systemd.services.nixlyos-autoupdate = {
    description = "NixlyOS nightly update + reboot (HTPC)";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    path = with pkgs; [ coreutils util-linux nix systemd ];
    serviceConfig.Type = "oneshot";
    script = ''
      set -u
      home=/home/${nixlyUser}
      stage="$home/.local/state/nixlyos/stage"
      flake="$home/.local/nixlyos"

      # Fresh lock + build as the user; stage.sh is a no-op when the
      # staged result is already current. Failures fall back to whatever
      # was staged earlier — never block the timer.
      runuser -u ${nixlyUser} -- /run/current-system/sw/bin/nixlyos-stage || true

      sys=$(readlink -f "$stage/result" 2>/dev/null || true)
      [ -n "$sys" ] && [ -e "$sys/bin/switch-to-configuration" ] || exit 0

      cur=$(readlink -f /run/current-system)
      booted=$(readlink -f /run/booted-system)
      [ "$sys" = "$cur" ] && [ "$sys" = "$booted" ] && exit 0

      if [ "$sys" != "$cur" ]; then
        # Adopt the staged lock so nixlyos-update's tree_key/stamp logic
        # agrees with what is now running.
        if [ -f "$stage/flake/flake.lock" ]; then
          runuser -u ${nixlyUser} -- cp "$stage/flake/flake.lock" "$flake/flake.lock" || true
        fi
        nix-env -p /nix/var/nix/profiles/system --set "$sys"
        "$sys/bin/switch-to-configuration" boot
      fi

      # Reboot completes the update (kernel/driver/session all land on the
      # new generation before anyone sits down at the TV).
      systemctl reboot
    '';
  };

  systemd.timers.nixlyos-autoupdate = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 06:00:00";
      # NOT Persistent: a missed 06:00 must not fire at power-on and reboot
      # the box under someone who just sat down. The background stager
      # still keeps the next generation ready; it lands next 06:00.
      Persistent = false;
      AccuracySec = "1min";
    };
  };
}
