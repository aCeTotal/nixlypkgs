{ pkgs, lib, ... }:

let
  # The privileged half of nixlytile's game mode. The script is a verbatim
  # copy of nixlytile:scripts/nixly-gametune — that file is the source of
  # truth, keep the two in sync. Everything it touches is auto-detected
  # (CPU driver, GPU vendor, exposed knobs) and every value is saved before
  # it is changed and restored on stop.
  #
  # No errexit wrapper: the script handles every failure itself (set -u
  # only), so a missing sysfs knob on one machine never kills the unit.
  gametune = pkgs.writeShellScriptBin "nixly-gametune" ''
    export PATH=${lib.makeBinPath (with pkgs; [
      coreutils
      gnugrep
      gawk
      procps
      util-linux
      systemd
      scx.rustscheds # scx_lavd, attached while a game runs
    ])}:/run/current-system/sw/bin
    ${builtins.readFile ./nixly-gametune}
  '';
in
{
  # On PATH for `nixly-gametune status` debugging.
  environment.systemPackages = [ gametune ];

  # Started/stopped by nixlytile when ultra game mode kicks in. The daemon
  # applies CPU/kernel/GPU tuning, attaches scx_lavd, holds
  # /dev/cpu_dma_latency at 0 us, and restores everything on stop — or by
  # itself if the compositor dies without stopping the unit.
  systemd.services.nixly-gametune = {
    description = "Low-latency tuning while a game is running";
    serviceConfig = {
      Type = "simple";
      ExecStart = "${gametune}/bin/nixly-gametune daemon";
      Restart = "no";
      RuntimeDirectory = "nixly-gametune";
      RuntimeDirectoryPreserve = "yes";
    };
  };

  # Per-game OOM + VRAM (dmem) protection; the game PID is the instance name.
  systemd.services."nixly-gameprio@" = {
    description = "OOM/VRAM protection for game PID %i";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${gametune}/bin/nixly-gametune protect %i";
      ExecStop = "${gametune}/bin/nixly-gametune unprotect %i";
      RuntimeDirectory = "nixly-gametune";
      RuntimeDirectoryPreserve = "yes";
    };
  };

  # Boot-time NVIDIA power-limit ceiling: costs nothing at idle (clocks
  # still scale down), only removes the factory cap under load. No state is
  # saved — this is the baseline a game-mode restore lands back on.
  systemd.services.nixly-gpumax = {
    description = "NVIDIA power-limit ceiling at boot";
    wantedBy = [ "multi-user.target" ];
    unitConfig.ConditionPathExists = "/sys/module/nvidia";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${gametune}/bin/nixly-gametune gpumax";
    };
  };

  # nixlytile starts and stops the units when ultra game mode kicks in.
  security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
      if (action.id == "org.freedesktop.systemd1.manage-units" &&
          subject.isInGroup("gamemode")) {
        var unit = action.lookup("unit");
        if (unit && (unit == "nixly-gametune.service" ||
            unit.indexOf("nixly-gameprio@") == 0)) {
          return polkit.Result.YES;
        }
      }
    });
  '';
}
