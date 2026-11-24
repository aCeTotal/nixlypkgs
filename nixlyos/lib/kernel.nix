# The kernel the panel profile chose.
{ config, lib, pkgs, hwData, ... }:
let
  cfg = config.nixlyos;
  catalogue = import ../../kernel/catalogue.nix;
  inherit (import ../../kernel/settings.nix { inherit lib; }) knobs available;
  entry = catalogue.${cfg.kernel};
  allowed = available entry;
  # Only values that differ from the kernel's own.
  changed = lib.filterAttrs (knob: value: allowed ? ${knob} && entry.defaults.${knob} != value) cfg.kernelSettings;
  ofKind = kind: lib.filterAttrs (knob: _: knobs.${knob}.kind == kind) changed;
  isArm = hwData.platform.arch == "aarch64";
in
{
  options.nixlyos = {
    kernel = lib.mkOption {
      type = lib.types.enum (lib.attrNames catalogue);
      default = "performance";
      description = "Kernel the profile chose.";
    };
    kernelSettings = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Kernel settings the profile changed.";
    };
  };

  config = lib.mkMerge [
    {
      assertions = [
        {
          assertion = lib.all (knob: lib.elem cfg.kernelSettings.${knob} (allowed.${knob} or [ ])) (lib.attrNames cfg.kernelSettings);
          message = "nixlyos.kernelSettings holds values the ${cfg.kernel} kernel does not offer.";
        }
        {
          assertion = !(config.boot.kernelPackages.kernel.config.isYes "CFI" && lib.elem "nvidia" config.services.xserver.videoDrivers);
          message = "The enterprise kernel runs in-tree drivers only; NVIDIA's driver needs another kernel.";
        }
      ];
    }

    (lib.mkIf isArm {
      boot.kernelPackages = pkgs.linuxPackages_latest;
      boot.kernelModules = [ "tcp_bbr" ];
      boot.kernel.sysctl."net.ipv4.tcp_congestion_control" = "bbr";
    })

    (lib.mkIf (!isArm) {
      boot.kernelPackages = pkgs.nixlyosKernel {
        name = cfg.kernel;
        inherit (hwData.resources) cpuLevel;
        build = ofKind "build";
      };
      boot.kernelParams = lib.mapAttrsToList (knob: value: "${knobs.${knob}.param}=${value}") (ofKind "boot");
      boot.kernel.sysctl = lib.mapAttrs' (knob: value: lib.nameValuePair knobs.${knob}.sysctl knobs.${knob}.options.${value}.value) (ofKind "sysctl");
    })

    (lib.mkIf entry.lockModules {
      systemd.services.nixly-module-lock = {
        description = "Lock kernel module loading";
        wantedBy = [ "multi-user.target" ];
        after = [ "systemd-modules-load.service" "systemd-udev-trigger.service" "network.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStartPre = "${config.systemd.package}/bin/udevadm settle";
          ExecStart = "${pkgs.procps}/bin/sysctl -w kernel.modules_disabled=1";
        };
      };
    })
  ];
}
