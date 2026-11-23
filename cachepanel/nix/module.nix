{ config, lib, pkgs, ... }:

let
  cfg = config.services.nixly-cachepanel;
  inherit (lib) mkOption types;
  stateDir = "/var/lib/cachepanel";
  githubRepo = builtins.match "https://github.com/([^/]+)/([^/]+)" (lib.removeSuffix ".git" (lib.removeSuffix "/" cfg.repository));
  generatedKey = "/var/lib/nixly-cachepanel-publish/id_ed25519";
  publishKey = if cfg.publish.keyFile == null then generatedKey else cfg.publish.keyFile;
  publishing = cfg.publish.remote != null;
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

    repository = mkOption {
      type = types.str;
      default = "https://github.com/aCeTotal/nixlypkgs";
      description = "Git repository of nixlypkgs.";
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

    publish = {
      remote = mkOption {
        type = types.nullOr types.str;
        default = if githubRepo == null then null else "git@github.com:${lib.elemAt githubRepo 0}/${lib.elemAt githubRepo 1}.git";
        defaultText = "the SSH form of repository on GitHub";
        description = "SSH remote the package wizard pushes to; null disables publishing.";
      };
      keyFile = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "/var/lib/secrets/nixlypkgs-deploy";
        description = "Deploy key for publish.remote, kept out of the store; null generates one the panel shows.";
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
        path = [ config.nix.package ];
        environment = {
          CACHEPANEL_DATABASE_URL = "postgres:///cachepanel?host=/run/postgresql";
          CACHEPANEL_STATE_DIR = stateDir;
          CACHEPANEL_HTTP_ADDR = cfg.listenAddress;
          CACHEPANEL_REPOSITORY = cfg.repository;
          CACHEPANEL_BRANCH = cfg.branch;
          CACHEPANEL_ADMIN_USER = cfg.admin.username;
          CACHEPANEL_ADMIN_PASSWORD_HASH = cfg.admin.passwordHash;
          CACHEPANEL_PUBLIC_URL = cfg.publicURL;
          CACHEPANEL_PUBLISH_REMOTE = lib.mkIf publishing cfg.publish.remote;
          CACHEPANEL_PUBLISH_KEY = lib.mkIf publishing "%d/publish-key";
          CACHEPANEL_CACHE_DIR = cfg.cache.dir;
          CACHEPANEL_CACHE_KEY = "%d/cache-key";
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
          LoadCredential = [ "cache-key:${cfg.cache.keyDir}/cache-priv.key" ] ++ lib.optional publishing "publish-key:${publishKey}";
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

    (lib.mkIf (publishing && cfg.publish.keyFile == null) {
      systemd.services.nixly-cachepanel-publish-key = {
        description = "Generate the package wizard's deploy key";
        wantedBy = [ "multi-user.target" ];
        before = [ "nixly-cachepanel.service" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        path = [ pkgs.openssh ];
        script = ''
          install -d -m 0700 ${dirOf generatedKey}
          if [ ! -f ${generatedKey} ]; then
            ssh-keygen -q -t ed25519 -N "" -C nixly-cachepanel -f ${generatedKey}
          fi
        '';
      };

      systemd.services.nixly-cachepanel = {
        after = [ "nixly-cachepanel-publish-key.service" ];
        requires = [ "nixly-cachepanel-publish-key.service" ];
      };
    })

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
  ]);
}
