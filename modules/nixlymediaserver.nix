{ config, lib, pkgs, ... }:

let
  cfg = config.services.nixlymediaserver;

  configFile = pkgs.writeText "config.conf" ''
    port=${toString cfg.port}
    db_path=${cfg.dataDir}/nixly.db
    upload_mbps=${toString cfg.uploadMbps}
    ${lib.optionalString (cfg.serverId != "") "server_id=${cfg.serverId}"}
    server_name=${cfg.serverName}
    tmdb_api_key=${cfg.tmdbApiKey}
    tmdb_language=${cfg.tmdbLanguage}
    cache_dir=${cfg.dataDir}/cache
    ${lib.concatMapStringsSep "\n" (p: "unprocessed_path=${p}") cfg.unprocessedPaths}
    ${lib.concatMapStringsSep "\n" (p: "converted_path=${p}") cfg.convertedPaths}
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
      description = "HTTP port the server listens on. Discovery (UDP) is always on port 8081.";
    };

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/nixlymediaserver";
      description = "Directory for database (nixly.db), image cache and runtime data.";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "nixlymedia";
      description = "User account under which the server runs.";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "nixlymedia";
      description = "Group under which the server runs.";
    };

    # ── Server identity (multi-server deduplication) ──────────────────

    serverId = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = ''
        Unique server ID for multi-server deduplication.
        Empty = auto-generated from hostname + random suffix (e.g. "myhost-3a7f1b2c").
        Clients use this to detect the same content across multiple servers.
      '';
    };

    serverName = lib.mkOption {
      type = lib.types.str;
      default = "Nixly Media Server";
      description = "Human-readable server name shown to clients.";
    };

    # ── Bandwidth & streaming ─────────────────────────────────────────

    uploadMbps = lib.mkOption {
      type = lib.types.int;
      default = 500;
      description = ''
        Upload bandwidth in Mbps. Controls two things:
        - Max concurrent streams: upload_mbps / 70 (assumes 70 Mbps per 4K lossless stream)
        - Server rating: upload_mbps / 100 (1-10 scale, used by clients to prefer faster servers)
        Set to 0 for unlimited.
      '';
    };

    # ── TMDB metadata ─────────────────────────────────────────────────

    tmdbApiKey = lib.mkOption {
      type = lib.types.str;
      default = "d415e076cfcbbe11dd7366a6e2f63321";
      description = "TMDB API key for fetching movie/show metadata, posters and backdrops.";
    };

    tmdbLanguage = lib.mkOption {
      type = lib.types.str;
      default = "en-US";
      description = ''
        Language for TMDB metadata (e.g. "en-US", "nb-NO").
        Affects titles, plot summaries and genre names.
      '';
    };

    # ── Source media paths (raw, unprocessed files) ───────────────────

    unprocessedPaths = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      example = [ "/mnt/bigdisk1/downloads" ];
      description = ''
        Directories containing raw media files to be scraped, renamed and moved.
        The server watches these with inotify and periodically rescans them.
        Files are classified (Movie / TV episode), matched against TMDB, then
        MOVED (rename, not copied) into
        <convertedPaths[0]>/nixly_ready_media/{Movies,TV/<Show>/Season<N>}/.
        No re-encoding is performed.
      '';
    };

    # ── Destination paths (ready media) ───────────────────────────────

    convertedPaths = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      example = [ "/mnt/bigdisk1/www/aceclan" ];
      description = ''
        Destination disks/directories for ready media.
        Scraped and renamed files are placed under
        <path>/nixly_ready_media/{Movies,TV/<Show>/Season<N>}/.
        The server also scans these on startup to populate the library and
        re-scrapes TMDB metadata for existing entries during full rescan.
      '';
    };

    # ── Firewall ──────────────────────────────────────────────────────

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Open firewall for the HTTP port (TCP) and discovery port 8081 (UDP).
        Discovery allows clients on the local network to find the server automatically.
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

    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0750 ${cfg.user} ${cfg.group} -"
      "d ${cfg.dataDir}/cache 0750 ${cfg.user} ${cfg.group} -"
    ];

    systemd.services.nixlymediaserver = {
      description = "Nixly Media Server";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      path = [ pkgs.ffmpeg-headless ];

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.group;
        WorkingDirectory = cfg.dataDir;
        ExecStart = "${cfg.package}/bin/nixly-server -c ${configFile}";

        Restart = "always";
        RestartSec = 5;

        # Hardening
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = "read-only";
        ReadWritePaths =
          [ cfg.dataDir ]
          ++ cfg.unprocessedPaths
          ++ cfg.convertedPaths;
        PrivateTmp = true;
      };
    };

    networking.firewall = lib.mkIf cfg.openFirewall {
      allowedTCPPorts = [ cfg.port ];
      allowedUDPPorts = [ 8081 ];
    };
  };
}
