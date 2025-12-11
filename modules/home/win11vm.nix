{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.programs.win11vm;
  hm = lib.hm;
in {
  options.programs.win11vm = {
    enable = mkEnableOption "Windows 11 VM (libvirt) via winintegration";

    vmName = mkOption {
      type = types.str;
      default = "win11";
      description = "Libvirt domain name for the Windows VM.";
    };

    connectionURI = mkOption {
      type = types.str;
      default = "qemu:///session";
      description = "Libvirt connection URI (user session recommended).";
    };

    maxMemoryMiB = mkOption {
      type = types.int;
      default = 8000;
      description = "Maximum memory in MiB for the VM (balloon ceiling).";
    };

    initMemoryMiB = mkOption {
      type = types.int;
      default = 1000;
      description = "Minimum memory in MiB for the VM (balloon floor).";
    };

    autoDefine = mkOption {
      type = types.bool;
      default = true;
      description = "Define/update the libvirt domain during Home Manager activation.";
    };
  };

  config = mkIf cfg.enable {
    # Ensure the tool and virt-manager are available to the user
    home.packages = [
      pkgs.winintegration
      pkgs.virt-manager
    ];

    # Define/update the VM automatically on activation
    home.activation.win11vm-define = mkIf cfg.autoDefine (hm.dag.entryAfter [ "writeBoundary" ] ''
      export LIBVIRT_DEFAULT_URI='${cfg.connectionURI}'
      export WIN_VM_NAME='${cfg.vmName}'
      export WIN_VM_MAX_MEM_MIB='${toString cfg.maxMemoryMiB}'
      export WIN_VM_MIN_MEM_MIB='${toString cfg.initMemoryMiB}'

      # Compose/define domain (idempotent)
      if command -v winintegration >/dev/null 2>&1; then
        winintegration define || true
      fi
    '');

    # Quick tip on first activation
    home.activation.win11vm-note = hm.dag.entryAfter [ "win11vm-define" ] ''
      echo "[win11vm] VM '${cfg.vmName}' defined in virt-manager (${cfg.connectionURI}). Attach your Windows ISO manually and start installation." >&2
    '';
  };
}
