{ config, lib, pkgs, ... }:

let
  rootFs = config.fileSystems."/";
  keepHourly = 24;
  keepDaily = 14;

  snapshot = pkgs.writeShellApplication {
    name = "nixly-snapshot";
    runtimeInputs = with pkgs; [ btrfs-progs coreutils util-linux ];
    text = ''
      dev=${rootFs.device}
      top=/run/nixly-snapshots
      mkdir -p "$top"
      mount -o subvolid=5,noatime "$dev" "$top"
      trap 'umount "$top"' EXIT

      dest="$top/@snapshots"
      [ -d "$dest" ] || btrfs subvolume create "$dest"
      chmod 700 "$dest"

      stamp=$(date +%Y%m%d-%H%M%S)
      hour=$(date +%H)

      keep() {
        # $1 prefix, $2 how many newest to keep
        # shellcheck disable=SC2012
        ls -1d "$dest/$1-"* 2>/dev/null | sort | head -n "-$2" | while read -r old; do
          btrfs subvolume delete "$old" >/dev/null
        done
      }

      for sv in @root @home; do
        btrfs subvolume snapshot -r "$top/$sv" "$dest/$sv-hourly-$stamp" >/dev/null
        if [ "$hour" = "04" ]; then
          btrfs subvolume snapshot -r "$top/$sv" "$dest/$sv-daily-$stamp" >/dev/null
        fi
        keep "$sv-hourly" ${toString keepHourly}
        keep "$sv-daily" ${toString keepDaily}
      done
    '';
  };
in
{
  # Read-only btrfs snapshots are the ransomware answer: encrypting malware
  # running as the user cannot rewrite them, and they live in a mount that
  # only exists inside this service's own namespace, so nothing else on the
  # system can even see the path.
  config = lib.mkIf (rootFs.fsType == "btrfs") {
    environment.systemPackages = [ snapshot ];

    systemd.services.nixly-snapshot = {
      description = "Read-only btrfs snapshots of / and /home";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${snapshot}/bin/nixly-snapshot";
        PrivateMounts = true;
        PrivateNetwork = true;
        ProtectHostname = true;
        ProtectKernelModules = true;
        ProtectKernelLogs = true;
        RestrictAddressFamilies = [ "AF_UNIX" ];
        SystemCallArchitectures = "native";
        IOSchedulingClass = "idle";
        Nice = 19;
      };
    };

    systemd.timers.nixly-snapshot = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "hourly";
        Persistent = true;
        RandomizedDelaySec = "5m";
      };
    };
  };
}
