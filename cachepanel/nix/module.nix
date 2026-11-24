{ config, lib, pkgs, ... }:

let
  cfg = config.services.nixly-cachepanel;
  inherit (lib) mkOption types;
  stateDir = "/var/lib/cachepanel";
  databaseURL = "postgres:///cachepanel?host=/run/postgresql";
  # sshd wants a root-owned path.
  sshCommand = "/etc/ssh/nixly-panel";
  updateDir = "${stateDir}/update";
in
{
  options.services.nixly-cachepanel = {
    enable = lib.mkEnableOption "the Nixly panel: binary cache, profiles and the package wizard";

    package = mkOption {
      type = types.package;
      description = "The cachepanel package.";
    };

    listenAddress = mkOption {
      type = types.str;
      default = "127.0.0.1:8686";
      description = "Address the panel listens on.";
    };

    branch = mkOption {
      type = types.str;
      default = "main";
      description = "Branch the panel follows.";
    };

    domain = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "cache.aceclan.no";
      description = "Caddy host serving the panel, the machine API and the binary cache.";
    };

    publicURL = mkOption {
      type = types.str;
      default = if cfg.domain == null then "http://${cfg.listenAddress}" else "https://${cfg.domain}";
      defaultText = lib.literalExpression ''"https://''${domain}"'';
      description = "Base URL machines fetch uploaded sources from.";
    };

    source = {
      seed = mkOption {
        type = types.str;
        default = "https://github.com/aCeTotal/nixlypkgs";
        description = "Repository copied into the panel's own source once, on first start.";
      };
      sshRemote = mkOption {
        type = types.nullOr types.str;
        default = if cfg.domain == null then null else "cachepanel@${cfg.domain}:source.git";
        defaultText = lib.literalExpression ''"cachepanel@''${domain}:source.git"'';
        description = "Git remote shown to pushers; null hides SSH push.";
      };
    };

    selfUpdate = {
      flake = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "/etc/nixos";
        description = "Flake of this server's NixOS configuration, rebuilt when the panel's source brings a new panel; null disables self-update.";
      };
      host = mkOption {
        type = types.str;
        default = config.networking.hostName;
        defaultText = lib.literalExpression "config.networking.hostName";
        description = "nixosConfigurations attribute to build.";
      };
      input = mkOption {
        type = types.str;
        default = "nixlypkgs";
        description = "Flake input that brings the panel.";
      };
    };

    admin = {
      username = mkOption {
        type = types.str;
        default = "nixlyos";
        description = "First administrator, created on an empty database.";
      };
      passwordHash = mkOption {
        type = types.str;
        default = import ./default-admin-hash.nix;
        description = "argon2id hash for the first administrator (default: nixos); make one with `cachepanel hash-password`.";
      };
    };

    cache = {
      dir = mkOption {
        type = types.str;
        default = "${stateDir}/cache";
        example = "/mnt/bigdisk2/nixlyos/cache";
        description = "Directory holding the signed binary cache; put it on a big disk.";
      };
      publicKey = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "cache.aceclan.no-1:qfGAXabgsofKSAqId9sqqbPlQic4l7gOGeWPrqUg3ak=";
        description = "Public half of the signing key; lets this host substitute from its own cache.";
      };
      keyName = mkOption {
        type = types.str;
        default = "cache.aceclan.no-1";
        description = "Signing key name machines trust.";
      };
      keyDir = mkOption {
        type = types.str;
        default = "/var/lib/nixly-cache/keys";
        description = "Directory holding cache-priv.key and cache-pub.key.";
      };
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      assertions = [{
        assertion = !(config.systemd.services ? nixlycaching);
        message = "nixly-cachepanel replaces the nixlycaching watcher; remove that module.";
      }];

      users.users.cachepanel = {
        isSystemUser = true;
        group = "cachepanel";
        home = stateDir;
        # sshd runs forced commands through it.
        useDefaultShell = true;
      };
      users.groups.cachepanel = { };

      services.postgresql = {
        enable = true;
        ensureDatabases = [ "cachepanel" ];
        ensureUsers = [{ name = "cachepanel"; ensureDBOwnership = true; }];
      };

      systemd.services.nixly-cachepanel = {
        description = "Nixly panel";
        wantedBy = [ "multi-user.target" ];
        after = [ "network-online.target" "postgresql.service" "nix-daemon.socket" "nixly-cache-keygen.service" ];
        wants = [ "network-online.target" ];
        requires = [ "postgresql.service" "nixly-cache-keygen.service" ];
        unitConfig.RequiresMountsFor = [ cfg.cache.dir ];
        path = [ config.nix.package pkgs.openssl pkgs.sbsigntool pkgs.efitools ];
        environment = {
          CACHEPANEL_DATABASE_URL = databaseURL;
          CACHEPANEL_STATE_DIR = stateDir;
          CACHEPANEL_HTTP_ADDR = cfg.listenAddress;
          CACHEPANEL_SOURCE_SEED = cfg.source.seed;
          CACHEPANEL_BRANCH = cfg.branch;
          CACHEPANEL_ADMIN_USER = cfg.admin.username;
          CACHEPANEL_ADMIN_PASSWORD_HASH = cfg.admin.passwordHash;
          CACHEPANEL_PUBLIC_URL = cfg.publicURL;
          CACHEPANEL_SSH_REMOTE = lib.mkIf (cfg.source.sshRemote != null) cfg.source.sshRemote;
          CACHEPANEL_UPDATE_DIR = lib.mkIf (cfg.selfUpdate.flake != null) updateDir;
          CACHEPANEL_CACHE_DIR = cfg.cache.dir;
          CACHEPANEL_CACHE_KEY = "%d/cache-key";
          CACHEPANEL_MICROSOFT_CERTS = "${pkgs.sbctl.src}/certs/microsoft";
          HOME = stateDir;
          NIX_REMOTE = "daemon";
          NIX_SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
          GIT_SSL_CAINFO = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
        };
        serviceConfig = {
          ExecStart = "${lib.getExe cfg.package} serve";
          User = "cachepanel";
          Group = "cachepanel";
          StateDirectory = "cachepanel";
          Restart = "always";
          RestartSec = "5s";
          LimitNOFILE = 1048576;
          LoadCredential = [ "cache-key:${cfg.cache.keyDir}/cache-priv.key" ];
          ReadWritePaths = [ cfg.cache.dir ];
          NoNewPrivileges = true;
          PrivateTmp = true;
          PrivateDevices = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          ProtectKernelTunables = true;
          ProtectKernelModules = true;
          ProtectKernelLogs = true;
          ProtectControlGroups = true;
          ProtectClock = true;
          ProtectHostname = true;
          RestrictSUIDSGID = true;
          RestrictRealtime = true;
          RestrictNamespaces = true;
          LockPersonality = true;
          RestrictAddressFamilies = [ "AF_UNIX" "AF_INET" "AF_INET6" ];
          SystemCallArchitectures = "native";
          CapabilityBoundingSet = "";
        };
      };
    }


    {
      systemd.tmpfiles.rules = [ "d ${cfg.cache.dir} 0755 cachepanel cachepanel -" ];

      systemd.services.nixly-cache-keygen = {
        description = "Generate the binary cache signing key";
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        path = [ config.nix.package ];
        script = ''
          # Root owns the path; Caddy serves the public key.
          install -d -m 0755 ${cfg.cache.keyDir}
          chown root:root ${dirOf cfg.cache.keyDir} ${cfg.cache.keyDir}
          chmod 0755 ${dirOf cfg.cache.keyDir} ${cfg.cache.keyDir}
          if [ ! -f ${cfg.cache.keyDir}/cache-priv.key ]; then
            nix-store --generate-binary-cache-key ${cfg.cache.keyName} ${cfg.cache.keyDir}/cache-priv.key ${cfg.cache.keyDir}/cache-pub.key
          fi
          chown root:root ${cfg.cache.keyDir}/cache-priv.key ${cfg.cache.keyDir}/cache-pub.key
          chmod 0600 ${cfg.cache.keyDir}/cache-priv.key
          chmod 0644 ${cfg.cache.keyDir}/cache-pub.key
        '';
      };

    }

    (lib.mkIf (cfg.cache.publicKey != null) {
      nix.settings = {
        extra-substituters = [ "file://${cfg.cache.dir}" ];
        extra-trusted-public-keys = [ cfg.cache.publicKey ];
      };
    })

    (lib.mkIf (cfg.domain != null) {
      services.caddy = {
        enable = true;
        virtualHosts.${cfg.domain}.extraConfig = ''
          encode zstd gzip

          handle /cache-pub.key {
            root * ${cfg.cache.keyDir}
            file_server
          }

          handle {
            reverse_proxy ${cfg.listenAddress}
          }
        '';
      };
      networking.firewall.allowedTCPPorts = [ 80 443 ];
    })

    (lib.mkIf (cfg.selfUpdate.flake != null) {
      systemd.tmpfiles.rules = [ "d ${updateDir} 0755 cachepanel cachepanel -" ];

      systemd.paths.nixly-cachepanel-update = {
        description = "Watch for panel update requests";
        wantedBy = [ "paths.target" ];
        pathConfig.PathChanged = "${updateDir}/request.json";
      };

      systemd.services.nixly-cachepanel-update = {
        description = "Rebuild the server for a new panel";
        # The switch must not stop its own caller.
        restartIfChanged = false;
        environment = {
          UPDATE_DIR = updateDir;
          FLAKE = cfg.selfUpdate.flake;
          HOST = cfg.selfUpdate.host;
          INPUT = cfg.selfUpdate.input;
          HEALTH_URL = "http://${cfg.listenAddress}/api/health";
        };
        serviceConfig = {
          Type = "oneshot";
          StateDirectory = "nixly-cachepanel-update";
          ExecStart = lib.getExe (pkgs.writeShellApplication {
            name = "nixly-cachepanel-update";
            runtimeInputs = [
              config.nix.package
              config.services.postgresql.package
              config.systemd.package
              pkgs.coreutils
              pkgs.curl
              pkgs.findutils
              pkgs.getent
              pkgs.git
              pkgs.gnugrep
              pkgs.jq
              pkgs.util-linux
            ];
            text = builtins.readFile ./self-update.sh;
          });
        };
      };
    })

    (lib.mkIf config.services.openssh.enable {
      environment.etc."ssh/nixly-panel" = {
        mode = "0755";
        text = ''
          #!${pkgs.runtimeShell}
          export CACHEPANEL_DATABASE_URL=${databaseURL} CACHEPANEL_STATE_DIR=${stateDir} CACHEPANEL_SSH_COMMAND=${sshCommand}
          exec ${lib.getExe cfg.package} "$@"
        '';
      };

      # Keys live in the panel; each may only run git.
      services.openssh.extraConfig = ''
        Match User cachepanel
          AuthorizedKeysFile none
          AuthorizedKeysCommand ${sshCommand} authorized-keys
          AuthorizedKeysCommandUser cachepanel
          PasswordAuthentication no
          KbdInteractiveAuthentication no
          PermitTTY no
          DisableForwarding yes
      '';
    })
  ]);
}
