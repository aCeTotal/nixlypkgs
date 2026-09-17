{ config, lib, pkgs, ... }:

let
  cfg = config.nixlyos.secureBoot;

  helper = pkgs.writeShellApplication {
    name = "nixly-secureboot";
    runtimeInputs = with pkgs; [ sbctl systemd coreutils gnugrep ];
    text = ''
      status() {
        sbctl status || true
        echo
        bootctl status 2>/dev/null | grep -iE "secure boot|tpm2" || true
      }

      setup() {
        [ "$(id -u)" = 0 ] || { echo "run as root"; exit 1; }
        sbctl create-keys
        if bootctl status 2>/dev/null | grep -qi "setup mode: *setup"; then
          # --microsoft keeps the vendor certs: without them the firmware
          # refuses its own option ROMs and a dual-booted Windows.
          sbctl enroll-keys --microsoft
          echo "keys enrolled — set nixlyos.secureBoot.enable = true, rebuild, reboot"
        else
          echo "firmware is not in setup mode: clear the platform keys in the"
          echo "UEFI menu (Security > Secure Boot > Key Management > delete all"
          echo "keys), boot back here and run 'nixly-secureboot setup' again."
        fi
      }

      case "''${1:-status}" in
        status) status ;;
        setup)  setup ;;
        verify) sbctl verify ;;
        *) echo "usage: nixly-secureboot [status|setup|verify]"; exit 1 ;;
      esac
    '';
  };
in
{
  options.nixlyos.secureBoot = {
    enable = lib.mkEnableOption "signed boot chain (lanzaboote + sbctl keys)";

    pkiBundle = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/sbctl";
      description = "Directory holding the Secure Boot signing keys.";
    };
  };

  config = lib.mkMerge [
    {
      environment.systemPackages = [ pkgs.sbctl helper ];

      # Measured boot is on regardless: the PCRs are what a later
      # LUKS-with-TPM unlock seals against.
      security.tpm2 = {
        enable = true;
        pkcs11.enable = true;
        tctiEnvironment.enable = true;
      };
    }

    (lib.mkIf cfg.enable {
      # lanzaboote replaces systemd-boot and signs the stub of every
      # generation at build time, so a kernel or nixpkgs bump is signed
      # before it ever reaches the ESP — updates cannot break the chain.
      boot.loader.systemd-boot.enable = lib.mkForce false;
      boot.lanzaboote = {
        enable = true;
        pkiBundle = cfg.pkiBundle;
        configurationLimit = config.boot.loader.systemd-boot.configurationLimit;
      };

      # Refuse to install an unsigned generation: with Secure Boot on in
      # firmware that is an unbootable machine.
      system.activationScripts.nixlySecureBootKeys = ''
        if [ ! -s ${cfg.pkiBundle}/keys/db/db.key ]; then
          echo "secure boot: no signing keys in ${cfg.pkiBundle}." >&2
          echo "run 'nixly-secureboot setup' or unset nixlyos.secureBoot.enable" >&2
          exit 1
        fi
      '';
    })
  ];
}
