{ lib, pkgs, biosBootDevice, ... }:

let
  pkiBundle = "/var/lib/sbctl";
  generations = 10;
  efi = biosBootDevice == null;
in
lib.mkMerge [
  {
    boot.initrd.systemd.enable = true;
    # Enrolled TPM tokens auto-unlock.
    boot.initrd.systemd.tpm2.enable = true;
    security.tpm2.enable = true;
    boot.tmp.useTmpfs = true;
    boot.loader.timeout = 3;
    environment.systemPackages = [ pkgs.sbctl ];
  }

  (lib.mkIf efi {
    boot.loader.systemd-boot.enable = lib.mkForce false;
    boot.loader.efi.canTouchEfiVariables = true;
    boot.lanzaboote = {
      enable = true;
      inherit pkiBundle;
      configurationLimit = generations;
      # Failed boots roll back.
      bootCounting.initialTries = 3;
    };

    # Bless only when reachable.
    systemd.services.nixlyserver-healthy = {
      description = "Confirm this generation is reachable";
      requiredBy = [ "boot-complete.target" ];
      before = [ "boot-complete.target" ];
      after = [ "multi-user.target" ];
      unitConfig.FailureAction = "reboot";
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.systemd}/bin/systemctl is-active --quiet sshd.service nftables.service tailscaled.service";
      };
    };
    systemd.targets.boot-complete.after = [ "multi-user.target" ];

    system.activationScripts.nixlyserverSecureBootKeys = ''
      if [ ! -s ${pkiBundle}/keys/db/db.key ]; then
        echo "secure boot: no signing keys in ${pkiBundle}; run 'sbctl create-keys'" >&2
        exit 1
      fi
    '';
  })

  (lib.mkIf (!efi) {
    boot.loader.grub = {
      enable = true;
      device = biosBootDevice;
      configurationLimit = generations;
    };
  })
]
