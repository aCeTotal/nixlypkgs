-- +goose Up
-- +goose StatementBegin
UPDATE modules SET
    source = replace(source, $old$
  secureboot =
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
              # Vendor certs keep option ROMs.
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
      imports = [ inputs.lanzaboote.nixosModules.lanzaboote ];

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

          # PCRs for later TPM unlock.
          security.tpm2 = {
            enable = true;
            pkcs11.enable = true;
            tctiEnvironment.enable = true;
          };
        }

        (lib.mkIf cfg.enable {
          # Signs every generation at build.
          boot.loader.systemd-boot.enable = lib.mkForce false;
          boot.lanzaboote = {
            enable = true;
            pkiBundle = cfg.pkiBundle;
            configurationLimit = config.boot.loader.systemd-boot.configurationLimit;
          };

          # Unsigned generations never install.
          system.activationScripts.nixlySecureBootKeys = ''
            if [ ! -s ${cfg.pkiBundle}/keys/db/db.key ]; then
              echo "secure boot: no signing keys in ${cfg.pkiBundle}." >&2
              echo "run 'nixly-secureboot setup' or unset nixlyos.secureBoot.enable" >&2
              exit 1
            fi
          '';
        })
      ];
    };
$old$, $new$
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
$new$),
    revision = revision + 1, updated_at = now()
WHERE slug = 'security' AND strpos(source, 'inputs.lanzaboote.nixosModules.lanzaboote') > 0;
-- +goose StatementEnd

-- +goose StatementBegin
UPDATE modules SET
    source = replace(replace(source, $old$
    hardware.xpadneo.enable = true;
    hardware.xone.enable = true;
$old$, $new$
    # In-tree xone needs dongle firmware.
    hardware.firmware = [ pkgs.xone-dongle-firmware ];
    # Its Wi-Fi driver grabs the dongle.
    boot.blacklistedKernelModules = [ "mt76x2u" ];
$new$), $old$
      extraModulePackages = with config.boot.kernelPackages; [
        xpadneo
        xone
      ];

$old$, E'\n'),
    revision = revision + 1, updated_at = now()
WHERE slug = 'gaming' AND strpos(source, 'hardware.xpadneo.enable = true;') > 0;
-- +goose StatementEnd

-- +goose StatementBegin
UPDATE modules SET
    source = replace(replace(replace(source, $old$
  msiEc =
    let
      kp = config.boot.kernelPackages;
      msiEcPkg = if kp ? msi-ec then kp.msi-ec else if kp ? msi_ec then kp.msi_ec else null;

      # Firmware versions the driver knows.
      fwList = pkgs.runCommand "msi-ec-firmware-list" { } ''
        grep -ohE '"[0-9A-Z]+E[A-Z0-9]+\.[0-9]+"' ${msiEcPkg.src}/msi-ec.c \
          | tr -d '"' | sort -u > $out
      '';

      # Pins unlisted firmware to a sibling.
      autoload = pkgs.writeShellScript "msi-ec-autoload" ''
        set -u
        export PATH=${lib.makeBinPath [ pkgs.kmod pkgs.coreutils pkgs.gnugrep ]}

        if modprobe msi-ec 2>/dev/null && [ -d /sys/devices/platform/msi-ec ]; then
          echo "msi-ec: EC-firmware stoettet direkte"
          exit 0
        fi

        modprobe ec_sys write_support=1 2>/dev/null || true
        io=/sys/kernel/debug/ec/ec0/io
        if [ ! -r "$io" ]; then
          echo "msi-ec: fant ikke $io — kan ikke lese EC-firmware"
          exit 0
        fi

        ver=$(dd if="$io" bs=1 skip=160 count=12 status=none | tr -cd '[:alnum:].')
        case "$ver" in
          *.*) ;;
          *) echo "msi-ec: ulesbar EC-firmware ('$ver')"; exit 0 ;;
        esac

        cand=$(grep -m1 "^''${ver%.*}\." ${fwList} || true)
        if [ -z "$cand" ]; then
          echo "msi-ec: EC-firmware $ver ikke stoettet (ingen konfig for ''${ver%.*})"
          exit 0
        fi

        echo "msi-ec: EC-firmware $ver ukjent for driveren — bruker konfig $cand"
        modprobe msi-ec firmware="$cand" || echo "msi-ec: lasting feilet"
        exit 0
      '';
    in
    {
      boot.extraModulePackages = lib.mkAfter (lib.optional (msiEcPkg != null) msiEcPkg);

      # msi-ec-autoload loads msi-ec.
      boot.kernelModules = lib.mkAfter [ "ec_sys" ];

      # Fan curves write the EC.
      boot.extraModprobeConfig = lib.mkAfter ''
        options ec_sys write_support=1
      '';

      services.udev.extraRules = ''
        ACTION=="add|change", SUBSYSTEM=="platform", KERNEL=="msi-ec", RUN+="/bin/sh -c 'chmod 0666 /sys/devices/platform/msi-ec/fan_mode /sys/devices/platform/msi-ec/shift_mode /sys/devices/platform/msi-ec/cooler_boost 2>/dev/null || true'"
      '';

      # Fans popup's validated EC writer.
      systemd.services.nixly-fand = {
        description = "nixlytile fan control helper";
        wantedBy = [ "multi-user.target" ];
        after = [ "systemd-modules-load.service" "msi-ec-autoload.service" ];
        serviceConfig = {
          Type = "exec";
          ExecStart = "${pkgs.nixlytile}/bin/nixly-fand";
          Restart = "on-failure";
          RestartSec = 5;
          NoNewPrivileges = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          PrivateTmp = true;
          PrivateNetwork = true;
          ProtectHostname = true;
          ProtectKernelModules = true;
          ProtectKernelLogs = true;
          ProtectControlGroups = true;
          RestrictAddressFamilies = [ "AF_UNIX" ];
          RestrictNamespaces = true;
          RestrictRealtime = true;
          LockPersonality = true;
          MemoryDenyWriteExecute = true;
          SystemCallArchitectures = "native";
          SystemCallFilter = [ "@system-service" "@raw-io" ];
          CapabilityBoundingSet = [ "CAP_SYS_RAWIO" "CAP_DAC_OVERRIDE" "CAP_CHOWN" ];
          # Control socket lives here.
          ReadWritePaths = [ "/run" ];
        };
      };

      systemd.services.msi-ec-autoload = lib.mkIf (msiEcPkg != null) {
        description = "Load msi-ec with a matching EC firmware configuration";
        after = [ "systemd-modules-load.service" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = autoload;
        };
      };
    };
$old$, $new$
  # In-tree msi-ec matches firmware siblings.
  msiEc = {
    boot.kernelModules = [ "msi-ec" ];

    # The compositor writes these directly.
    services.udev.extraRules = ''
      ACTION=="add|change|bind", SUBSYSTEM=="platform", KERNEL=="msi-ec", RUN+="/bin/sh -c 'cd /sys/devices/platform/msi-ec && chmod 0666 fan_mode shift_mode cooler_boost cpu/fan_curve gpu/fan_curve 2>/dev/null || true'"
    '';

    # pwm and NVML fans.
    systemd.services.nixly-fand = {
      description = "nixlytile fan control helper";
      wantedBy = [ "multi-user.target" ];
      after = [ "systemd-modules-load.service" ];
      serviceConfig = {
        Type = "exec";
        ExecStart = "${pkgs.nixlytile}/bin/nixly-fand";
        Restart = "on-failure";
        RestartSec = 5;
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        PrivateNetwork = true;
        ProtectHostname = true;
        ProtectKernelModules = true;
        ProtectKernelLogs = true;
        ProtectControlGroups = true;
        RestrictAddressFamilies = [ "AF_UNIX" ];
        RestrictNamespaces = true;
        RestrictRealtime = true;
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        SystemCallArchitectures = "native";
        SystemCallFilter = [ "@system-service" ];
        CapabilityBoundingSet = [ "CAP_DAC_OVERRIDE" "CAP_CHOWN" ];
        # Control socket lives here.
        ReadWritePaths = [ "/run" ];
      };
    };
  };
$new$), $old$
  ++ map (name: gpus.${renamedGpus.${name} or name}) hwData.selection.gpus
$old$, $new$
  ++ map (name: gpus.${renamedGpus.${name} or name}) hwData.selection.gpus
  ++ [ enterpriseGpu ]
$new$), $old$
  # GBM for the greeter.
$old$, $new$
  # Enterprise runs in-tree drivers only.
  enterpriseGpu = {
    assertions = [{
      assertion = config.nixlyos.kernel != "enterprise" || !(builtins.elem "nvidia" config.services.xserver.videoDrivers);
      message = "The enterprise kernel runs in-tree drivers only; NVIDIA's driver needs the performance kernel.";
    }];
  };

  # GBM for the greeter.
$new$),
    revision = revision + 1, updated_at = now()
WHERE slug = 'hardware' AND strpos(source, 'msi-ec-autoload') > 0;
-- +goose StatementEnd

UPDATE modules SET
    source = replace(source, 'after = [ "msi-ec-autoload.service" ];', 'after = [ "systemd-modules-load.service" ];'),
    revision = revision + 1, updated_at = now()
WHERE slug = 'system' AND strpos(source, 'msi-ec-autoload.service') > 0;

INSERT INTO module_revisions (module_id, revision, source)
SELECT id, revision, source FROM modules WHERE slug IN ('system', 'security', 'gaming', 'hardware')
ON CONFLICT DO NOTHING;

-- +goose Down
SELECT 1;
