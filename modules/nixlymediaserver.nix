{ config, lib, pkgs, ... }:

let
  cfg = config.services.nixlymediaserver;

  configFile = pkgs.writeText "nixlymediaserver.conf" ''
    port = ${toString cfg.port}
    db_path = ${cfg.dataDir}/nixly.db
    cache_dir = ${cfg.dataDir}/cache
    upload_mbps = ${toString cfg.uploadMbps}
    ${lib.optionalString (cfg.serverId != "") "server_id = ${cfg.serverId}"}
    server_name = ${cfg.serverName}
    tmdb_api_key = ${cfg.tmdbApiKey}
    tmdb_language = ${cfg.tmdbLanguage}
    tv_download_path = ${cfg.tvDownloadPath}
    movie_download_path = ${cfg.movieDownloadPath}
    auth_user = ${cfg.authUser}
    auth_password = ${cfg.authPassword}
    ${lib.concatMapStringsSep "\n" (p: "media_path = ${p}") cfg.mediaPaths}
  '';
in
{
  options.services.nixlymediaserver = {
    enable = lib.mkEnableOption "Nixly Media Server";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.nixlymediaserver;
      description = "The nixlymediaserver package to use.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8080;
      description = "HTTP port. Discovery (UDP) is fixed on 8081.";
    };

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/nixlymediaserver";
      description = "Directory for the SQLite database (nixly.db) and image cache.";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "nixlymedia";
      description = "User the service runs as.";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "nixlymedia";
      description = "Group the service runs as.";
    };

    # ── Identity ──────────────────────────────────────────────────────

    serverId = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = ''
        Stable server ID for multi-server deduplication.
        Empty = auto-generated from hostname + random suffix.
      '';
    };

    serverName = lib.mkOption {
      type = lib.types.str;
      default = "Nixly Media Server";
      description = "Human-readable server name shown to clients.";
    };

    # ── Bandwidth ─────────────────────────────────────────────────────

    uploadMbps = lib.mkOption {
      type = lib.types.int;
      default = 500;
      description = ''
        Advertised upload bandwidth in Mbps. Informational only — no
        per-stream throttle is applied. The hard cap is 3 concurrent
        distinct client IPs (set in source).
      '';
    };

    # ── Auth ──────────────────────────────────────────────────────────

    authUser = lib.mkOption {
      type = lib.types.str;
      default = "nixly";
      description = "HTTP Basic Auth username applied to all routes.";
    };

    authPassword = lib.mkOption {
      type = lib.types.str;
      default = "nixlyadmin";
      description = ''
        HTTP Basic Auth password. The default is fine for trusted LANs;
        change it for any deployment reachable from outside the LAN.
      '';
    };

    # ── TMDB ──────────────────────────────────────────────────────────

    tmdbApiKey = lib.mkOption {
      type = lib.types.str;
      default = "d415e076cfcbbe11dd7366a6e2f63321";
      description = "TMDB API key for metadata + poster/backdrop downloads.";
    };

    tmdbLanguage = lib.mkOption {
      type = lib.types.str;
      default = "en-US";
      description = "TMDB language code (e.g. en-US, nb-NO).";
    };

    # ── Library + downloads ───────────────────────────────────────────

    mediaPaths = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      example = [ "/srv/media/TV" "/srv/media/Movies" ];
      description = ''
        Directories scanned + watched (inotify) for media files.
        The TV and movie download paths are auto-appended at runtime so
        files fetched via the /wget UI also end up in the library.
      '';
    };

    tvDownloadPath = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/nixlymediaserver/TV";
      description = "Destination directory for TV downloads from the /wget UI.";
    };

    movieDownloadPath = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/nixlymediaserver/Movies";
      description = "Destination directory for movie downloads from the /wget UI.";
    };

    # ── Firewall ──────────────────────────────────────────────────────

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Open the HTTP port (TCP) and discovery port 8081 (UDP) in the
        firewall.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.${cfg.user} = lib.mkIf (cfg.user == "nixlymedia") {
      isSystemUser = true;
      group = cfg.group;
      home = cfg.dataDir;
      description = "Nixly Media Server user";
    };
    users.groups.${cfg.group} = lib.mkIf (cfg.group == "nixlymedia") { };

    # Raise inotify watch limit — large libraries blow past the 8192 default.
    boot.kernel.sysctl."fs.inotify.max_user_watches" = lib.mkDefault 524288;

    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0750 ${cfg.user} ${cfg.group} - -"
      "d ${cfg.dataDir}/cache 0750 ${cfg.user} ${cfg.group} - -"
      "d ${cfg.tvDownloadPath} 0755 ${cfg.user} ${cfg.group} - -"
      "d ${cfg.movieDownloadPath} 0755 ${cfg.user} ${cfg.group} - -"
    ];

    systemd.services.nixlymediaserver = {
      description = "Nixly Media Server";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      path = [ pkgs.ffmpeg-headless ];

      environment = {
        NIXLY_NO_BROWSER = "1";
        HOME = cfg.dataDir;
      };

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.group;
        WorkingDirectory = cfg.dataDir;
        ExecStart = "${cfg.package}/bin/nixly-server -c ${configFile}";

        Restart = "always";
        RestartSec = 5;

        # Allow many concurrent streams + watching large libraries.
        LimitNOFILE = 65536;

        # Hardening — read-mostly server with writes confined to dataDir,
        # cache, and the configured media + download paths.
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = "read-only";
        ReadWritePaths =
          [ cfg.dataDir cfg.tvDownloadPath cfg.movieDownloadPath ]
          ++ cfg.mediaPaths;
        PrivateTmp = true;
      };
    };

    networking.firewall = lib.mkIf cfg.openFirewall {
      allowedTCPPorts = [ cfg.port ];
      allowedUDPPorts = [ 8081 ];
    };
  };
}
