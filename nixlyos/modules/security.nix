{ config, lib, pkgs, inputs, hwData, ... }:

let
  firewall = {
    networking.firewall.enable = true;
    # One transaction at boot.
    networking.nftables.enable = true;
    # No free LAN discovery.
    networking.firewall.allowPing = false;

    # Crashes never spill memory.
    systemd.coredump.enable = false;

    security.apparmor.enable = false;
  };

  # Steam stays unjailed for Proton.
  sandbox =
    let
      # Blocks the systemd1 escape.
      dbusFilter = [
        "--dbus-user=filter"
        "--dbus-user.talk=org.freedesktop.Notifications"
        "--dbus-user.talk=org.freedesktop.secrets"
        "--dbus-user.talk='org.freedesktop.portal.*'"
        "--dbus-user.talk=org.freedesktop.ScreenSaver"
        "--dbus-user.talk=ca.desrt.dconf"
        "--dbus-user.own='org.mpris.MediaPlayer2.*'"
      ];
      dbusArgs = builtins.concatStringsSep " \\\n          " dbusFilter;

      jail = final: { pkg, bin, profile, extraArgs ? [ ] }:
        final.symlinkJoin {
          name = "${bin}-jailed";
          paths = [ pkg ];
          inherit (pkg) meta;
          postBuild = ''
            rm -f $out/bin/${bin}
            cat > $out/bin/${bin} <<'EOF'
            #!${final.runtimeShell} -e
            # Options first: joining rejects them after.
            exec /run/wrappers/bin/firejail --quiet \
              ${builtins.concatStringsSep " " extraArgs} \
              --profile=${final.firejail}/etc/firejail/${profile}.profile \
              ${dbusArgs} \
              --join-or-start=${bin} ${pkg}/bin/${bin} "$@"
            EOF
            chmod 0755 $out/bin/${bin}

            # Launchers hardcode the unwrapped store path.
            for d in $out/share/applications/*.desktop; do
              [ -e "$d" ] || continue
              real=$(readlink -f "$d")
              rm "$d"
              substitute "$real" "$d" --replace-quiet "${pkg}/bin/${bin}" "$out/bin/${bin}"
            done
          '';
        };
    in
    {
      programs.firejail.enable = true;

      # firejail spawns it from PATH.
      environment.systemPackages = [ pkgs.xdg-dbus-proxy ];

      nixpkgs.overlays = [
        (final: prev: {
          brave = jail final {
            pkg = prev.brave;
            bin = "brave";
            profile = "brave-browser";
            extraArgs = [
              "'--ignore=whitelist \${HOME}/.gnupg'"
              "--private-tmp"
              # GTK theme reads wallpaper colours.
              "'--whitelist=\${HOME}/.local/state/nixly-theme'"
              "'--read-only=\${HOME}/.local/state/nixly-theme'"
            ];
          };
        })
      ];

      # Portal file picks into firejail.
      systemd.services.nixly-jaild = {
        description = "nixlytile sandbox file grant helper";
        wantedBy = [ "multi-user.target" ];
        path = [ pkgs.polkit ];
        serviceConfig = {
          Type = "exec";
          ExecStart = "${pkgs.nixlytile}/bin/nixly-jaild";
          Restart = "on-failure";
          RestartSec = 5;
          NoNewPrivileges = true;
          ProtectSystem = "strict";
          ReadWritePaths = [ "/run" ];
          ProtectHome = "read-only";
          ProtectHostname = true;
          ProtectKernelTunables = true;
          ProtectKernelModules = true;
          ProtectKernelLogs = true;
          ProtectControlGroups = true;
          PrivateNetwork = true;
          RestrictAddressFamilies = [ "AF_UNIX" ];
          RestrictNamespaces = [ "mnt" ];
          RestrictRealtime = true;
          LockPersonality = true;
          MemoryDenyWriteExecute = true;
          SystemCallArchitectures = "native";
          SystemCallFilter = [ "@system-service" "@mount" "setns" ];
          CapabilityBoundingSet = [
            "CAP_SYS_ADMIN"
            "CAP_SYS_CHROOT"
            "CAP_SYS_PTRACE"
            "CAP_DAC_OVERRIDE"
            "CAP_DAC_READ_SEARCH"
            "CAP_CHOWN"
            "CAP_SETUID"
            "CAP_SETGID"
          ];
        };
      };

      # File picks never prompt.
      security.polkit.extraConfig = ''
        polkit.addRule(function(action, subject) {
          if (action.id == "org.nixlytile.jail-grant" && subject.local && subject.active) {
            return polkit.Result.YES;
          }
        });
      '';
    };

  surface =
    let
      # Last peer gone: boltd exits.
      boltIdle = pkgs.writeShellScript "bolt-idle" ''
        for d in /sys/bus/thunderbolt/devices/*-*; do
          case ''${d##*/} in *-0|*:*) continue ;; esac
          [ -e "$d" ] && exit 0
        done
        exec ${pkgs.systemd}/bin/systemctl stop --no-block bolt.service
      '';
    in
    {
      # Unused code hostile devices reach.
      boot.blacklistedKernelModules = [
        "firewire-core"
        "firewire-ohci"
        "firewire-sbp2"

        "dccp"
        "sctp"
        "rds"
        "tipc"
        "n-hdlc"
        "ax25"
        "netrom"
        "x25"
        "rose"
        "decnet"
        "econet"
        "af_802154"
        "ipx"
        "appletalk"
        "psnap"
        "p8023"
        "p8022"
        "atm"

        "cramfs"
        "freevxfs"
        "jffs2"
        "hfs"
        "hfsplus"
        "gfs2"
        "ksmbd"

        "vivid"
      ] ++ lib.optionals (hwData.platform.arch != "aarch64") [
        "parport_pc"
        "ppdev"
      ];

      # BIOS must require user authorization.
      services.hardware.bolt.enable = true;

      # Only a plugged peer wakes boltd.
      services.udev.extraRules = ''
        SUBSYSTEM=="thunderbolt", ENV{DEVTYPE}!="thunderbolt_device", ENV{SYSTEMD_WANTS}=""
        SUBSYSTEM=="thunderbolt", KERNEL=="*-0", ENV{SYSTEMD_WANTS}=""
        ACTION=="remove", SUBSYSTEM=="thunderbolt", ENV{DEVTYPE}=="thunderbolt_device", RUN+="${boltIdle}"
      '';
    };

  # The panel's CA anchors the chain.
  secureboot = {
    imports = [
      (lib.mkRemovedOptionModule [ "nixlyos" "secureBoot" "enable" ] "The panel's NixlyOS CA signs the boot chain; run nixlyos-secureboot enroll.")
      (lib.mkRemovedOptionModule [ "nixlyos" "secureBoot" "pkiBundle" ] "Machines hold no Secure Boot keys.")
    ];

    environment.systemPackages = [ pkgs.nixlyos-secureboot ];

    # PCRs for later TPM unlock.
    security.tpm2 = {
      enable = true;
      pkcs11.enable = true;
      tctiEnvironment.enable = true;
    };
  };

  # Malware cannot rewrite them.
  snapshots =
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
    lib.mkIf (rootFs.fsType == "btrfs") {
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
in
{
  imports = [
    firewall
    sandbox
    surface
    secureboot
    snapshots
  ];
}
