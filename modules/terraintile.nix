{ config, lib, pkgs, ... }:

let
  cfg = config.services.terraintile;
in
{
  options.services.terraintile = {
    # Importing this module is opting in: the server comes up on the
    # network with zero further configuration.
    enable = lib.mkEnableOption "TerrainTile terrain pipeline server" // {
      default = true;
    };

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.terraintile;
      description = "The terraintile package to use.";
    };

    host = lib.mkOption {
      type = lib.types.str;
      default = "0.0.0.0";
      description = "Address to bind the web UI to.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 6650;
      description = "HTTP port for the web UI and tile data.";
    };

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/terraintile";
      description = ''
        Working directory and HOME of the service. The web UI's file
        browser starts here — place height data (GeoTIFF/ZIP) somewhere
        below it, and point the output there too.
      '';
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "terraintile";
      description = "User the service runs as.";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "terraintile";
      description = "Group the service runs as.";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Open the HTTP port (TCP) in the firewall.";
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.${cfg.user} = lib.mkIf (cfg.user == "terraintile") {
      isSystemUser = true;
      group = cfg.group;
      home = cfg.dataDir;
      description = "TerrainTile server user";
    };
    users.groups.${cfg.group} = lib.mkIf (cfg.group == "terraintile") { };

    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0750 ${cfg.user} ${cfg.group} - -"
    ];

    systemd.services.terraintile = {
      description = "TerrainTile terrain pipeline server";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];

      environment = {
        HOME = cfg.dataDir;
      };

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.group;
        WorkingDirectory = cfg.dataDir;
        ExecStart = "${lib.getExe cfg.package} --host ${cfg.host} --port ${toString cfg.port}";

        Restart = "always";
        RestartSec = 5;

        # Tile processing opens one VRT handle per worker thread plus
        # thousands of small tile files.
        LimitNOFILE = 65536;

        # Hardening — writes confined to dataDir; homes stay readable so
        # height data can be picked from the file browser.
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = "read-only";
        ReadWritePaths = [ cfg.dataDir ];
        PrivateTmp = true;
      };
    };

    networking.firewall = lib.mkIf cfg.openFirewall {
      allowedTCPPorts = [ cfg.port ];
    };
  };
}
